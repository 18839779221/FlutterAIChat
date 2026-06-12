import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Scriptable in-memory [WebViewPlatform] so widget tests can exercise the
/// real `WebViewController` code paths (document loads, navigation callbacks,
/// runtime applies) instead of the no-platform error fallback.
///
/// Register with `WebViewPlatform.instance = FakeWebViewPlatform()`. The
/// instance cannot be reset to null, so only register it in test files that
/// want the real controller paths — files relying on the "no platform
/// configured" error fallback are isolated per-suite and stay unaffected.
class FakeWebViewPlatform extends WebViewPlatform {
  final List<FakePlatformWebViewController> controllers =
      <FakePlatformWebViewController>[];
  final List<FakePlatformNavigationDelegate> navigationDelegates =
      <FakePlatformNavigationDelegate>[];

  /// When true (default), every `loadHtmlString` schedules an
  /// `onPageFinished('about:blank')` microtask on its controller.
  bool autoCompletePageLoads = true;

  /// Overrides the result of `runJavaScriptReturningResult`. Defaults to the
  /// Android-style JSON-quoted `'"success"'` when null.
  Object Function(String javaScript)? javaScriptResultHandler;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakePlatformWebViewController(params, this);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    final delegate = FakePlatformNavigationDelegate(params);
    navigationDelegates.add(delegate);
    return delegate;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakePlatformWebViewWidget(params);
  }
}

class FakePlatformWebViewController extends PlatformWebViewController {
  FakePlatformWebViewController(super.params, this.platform)
      : super.implementation();

  final FakeWebViewPlatform platform;
  final List<String> loadedHtmlStrings = <String>[];
  final List<String> runJavaScriptReturningResultCalls = <String>[];
  final Map<String, JavaScriptChannelParams> javaScriptChannels =
      <String, JavaScriptChannelParams>{};
  FakePlatformNavigationDelegate? navigationDelegate;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> enableZoom(bool enabled) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigationDelegate = handler as FakePlatformNavigationDelegate;
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    javaScriptChannels[javaScriptChannelParams.name] = javaScriptChannelParams;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    loadedHtmlStrings.add(html);
    if (platform.autoCompletePageLoads) {
      scheduleMicrotask(() => firePageFinished());
    }
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    runJavaScriptReturningResultCalls.add(javaScript);
    final handler = platform.javaScriptResultHandler;
    if (handler != null) {
      return handler(javaScript);
    }
    return '"success"';
  }

  @override
  Future<void> runJavaScript(String javaScript) async {}

  void firePageFinished([String url = 'about:blank']) {
    navigationDelegate?.onPageFinished?.call(url);
  }

  void fireWebResourceError(WebResourceError error) {
    navigationDelegate?.onWebResourceError?.call(error);
  }
}

class FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }
}

class FakePlatformWebViewWidget extends PlatformWebViewWidget {
  FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
