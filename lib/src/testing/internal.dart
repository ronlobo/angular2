import 'dart:async';

import 'package:angular2/core.dart' show PLATFORM_INITIALIZER;
import 'package:angular2/platform/testing/browser.dart';
import 'package:angular2/src/core/di/provider.dart' show provide, Provider;
import 'package:angular2/src/core/reflection/reflection.dart';
import 'package:angular2/src/core/reflection/reflection_capabilities.dart';
import "package:angular2/src/core/zone/ng_zone.dart" show NgZone;
import "package:angular2/src/platform/dom/dom_adapter.dart" show DOM;
import 'package:test/test.dart';

import "internal_injector.dart";

export "fake_async.dart";
export "internal_injector.dart";
export "test_component_builder.dart";
export "utils.dart";

/// Allows injecting dependencies in [setUp()] and [test()].
///
/// Example:
///
///   test('...', inject([AClass], (object) => {
///     object.doSomething();
///     expect(...);
///   });
///
///   setUp(inject([Dependency, AClass], (dep, object) => {
///    // some code that uses `dep` and `object`
///    // ...
///   });
///
Future<dynamic> inject(List<dynamic> tokens, Function fn) async {
  _bootstrapInternalTests();
  _testInjector.reset();
  // Mark test as not async.
  AsyncTestCompleter.currentTestFuture = null;
  FunctionWithParamTokens funcWithParams = fn is FunctionWithParamTokens
      ? fn
      : new FunctionWithParamTokens(tokens, fn);
  if (funcWithParams.isAsync) {
    Provider p = provide(AsyncTestCompleter);
    assert(p != null);
    _testInjector.addProviders([funcWithParams.completer]);
  }
  if (_extraPerTestProviders != null) {
    if (_extraPerTestProviders != null)
      _testInjector.addProviders(_extraPerTestProviders);
  }

  _inTest = true;
  _testInjector.execute(funcWithParams);
  _inTest = false;
  if (AsyncTestCompleter.currentTestFuture != null) {
    await AsyncTestCompleter.currentTestFuture;
    return AsyncTestCompleter.currentTestFuture;
  }
}

/// Allows overriding default providers defined in test_injector.js.
///
///  The given function must return a list of DI providers.
///
///  Example:
///
///    beforeEachProviders(() => [
///        provide(Compiler).toClass(MockCompiler),
///        provide(SomeToken).toValue(myValue),
///    ]);
///
void beforeEachProviders(Function fn) {
  _extraPerTestProviders = fn();
}

TestInjector _testInjector = TestInjector.singleton();
bool _inTest = false;
// Set on one-time initialization of tests for platform.
bool _bootstrap_initialized = false;
// Providers for specific Platform.
List _platformProviders;
List _applicationProviders;
List _extraPerTestProviders;

void _bootstrapInternalTests() {
  _platformProviders ??= TEST_BROWSER_PLATFORM_PROVIDERS;
  _applicationProviders ??= TEST_BROWSER_APPLICATION_PROVIDERS;
  if (_bootstrap_initialized) return;
  _bootstrap_initialized = true;
  reflector.reflectionCapabilities = new ReflectionCapabilities();
  _setBaseTestProviders(_platformProviders, _applicationProviders);
}

/// Set the providers that the test injector should use.
///
/// These should be providers common to every test in the suite.
void _setBaseTestProviders(
    List<dynamic /* Type | Provider | List < dynamic > */ > platformProviders,
    List<
        dynamic /* Type | Provider | List < dynamic > */ > applicationProviders) {
  var testInjector = TestInjector.singleton();
  if (testInjector.platformProviders.length > 0 ||
      testInjector.applicationProviders.length > 0) {
    // This may only be called once, to set up the common providers for the
    // current test suite on the current platform.
    throw new StateError(
        'Cannot set base providers because it has already been called');
  }
  testInjector.platformProviders = platformProviders;
  testInjector.applicationProviders = applicationProviders;
  var injector = testInjector.createInjector();
  List<Function> initializers =
      injector.get(PLATFORM_INITIALIZER, null) as List<Function>;
  initializers?.forEach((init) => init());
  testInjector.reset();
}

bool isInInnerZone() => NgZone.isInAngularZone();

class _HasTextContent extends Matcher {
  final String expectedText;
  const _HasTextContent(this.expectedText);
  bool matches(item, Map matchState) => _elementText(item) == expectedText;
  Description describe(Description description) =>
      description.add('$expectedText');
  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    mismatchDescription.add('Text content of element: '
        '\'${_elementText(item)}\'');
    return mismatchDescription;
  }
}

Matcher hasTextContent(expected) => new _HasTextContent(expected);

class _ThrowsWith extends Matcher {
  // RegExp or String.
  final expected;
  String exceptionStr;

  _ThrowsWith(this.expected) {
    assert(expected is RegExp || expected is String);
  }

  bool matches(item, Map matchState) {
    try {
      item();
    } catch (e) {
      exceptionStr = e.toString();
      if (expected is String) {
        return exceptionStr.contains(expected);
      }
      return (expected as RegExp).hasMatch(exceptionStr);
    }
    return false;
  }

  Description describe(Description description) => description.add('$expected');

  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    mismatchDescription.add('Expecting throw \'${expected}\' '
        ' got \'$exceptionStr\'');
    return mismatchDescription;
  }
}

Matcher throwsWith(message) => new _ThrowsWith(message);

String _elementText(n) {
  hasNodes(n) {
    var children = DOM.childNodes(n);
    return children != null && children.length > 0;
  }

  if (n is Iterable) {
    return n.map(_elementText).join("");
  }

  if (DOM.isCommentNode(n)) {
    return '';
  }

  if (DOM.isElementNode(n) && DOM.tagName(n) == 'CONTENT') {
    return _elementText(DOM.getDistributedNodes(n));
  }

  if (DOM.hasShadowRoot(n)) {
    return _elementText(DOM.childNodesAsList(DOM.getShadowRoot(n)));
  }

  if (hasNodes(n)) {
    return _elementText(DOM.childNodesAsList(n));
  }

  return DOM.getText(n);
}
