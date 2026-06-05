import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_chat/models/artifact/artifact_render_session_snapshot.dart';
import 'package:ai_chat/services/artifact/artifact_render_session_recorder.dart';
import 'package:ai_chat/services/artifact/artifact_host_style_builder.dart';
import 'package:ai_chat/services/artifact/artifact_theme_token_mapper.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_page_storage.dart';
import 'package:ai_chat/widgets/tool_renderers/tool_running_effects.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const double _minArtifactPreviewHeight = 180;
const double _defaultArtifactPreviewHeight = 260;
const double _maxArtifactPreviewScreenCount = 3;
const String _artifactHeightChannelName = 'ArtifactHeight';
const String _artifactRenderStateChannelName = 'ArtifactRenderState';
const String artifactPreviewTruncationMessage = '内容较长，长按进入详情页查看完整内容。';
const Duration _streamingDebounceDelay = Duration(milliseconds: 1000);
const Duration _heightUpdateDebounceDelay = Duration(milliseconds: 100);
const String _artifactPreviewLogTag = 'ArtifactPreviewSurface';
const String _artifactPreviewSweepShellKey = 'artifact-preview-sweep-shell';

double clampArtifactPreviewHeight(
  double rawHeight, {
  required double viewportHeight,
}) {
  if (!rawHeight.isFinite) {
    return _defaultArtifactPreviewHeight;
  }
  final resolvedViewportHeight = viewportHeight.isFinite && viewportHeight > 0
      ? viewportHeight
      : _defaultArtifactPreviewHeight;
  final maxArtifactPreviewHeight =
      resolvedViewportHeight * _maxArtifactPreviewScreenCount;
  return rawHeight
      .clamp(
        _minArtifactPreviewHeight,
        maxArtifactPreviewHeight,
      )
      .toDouble();
}

/// Builds a constrained HTML document for native artifact preview.
String buildArtifactPreviewDocument({
  bool lockScroll = true,
  Map<String, String> hostCssVariables = const <String, String>{},
}) {
  final hostStyles = buildArtifactPreviewHostStyles(hostCssVariables);
  final headInjection = '''
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob: https: http:; style-src 'unsafe-inline' data: https: http:; font-src data: https: http:; script-src 'unsafe-inline' 'unsafe-eval' data: blob:; connect-src 'none'; media-src data: blob:; frame-src data: blob:; object-src 'none'; base-uri 'none'; form-action 'none'; navigate-to 'none'">
<base target="_self">
<script>
  (function() {
    const lockScroll = () => {
      if (document.documentElement) {
        document.documentElement.style.overflow = '${lockScroll ? 'hidden' : 'auto'}';
        document.documentElement.style.touchAction = '${lockScroll ? 'none' : 'auto'}';
      }
      if (document.body) {
        document.body.style.overflow = '${lockScroll ? 'hidden' : 'auto'}';
        document.body.style.touchAction = '${lockScroll ? 'none' : 'auto'}';
      }
    };
    const isFullDocumentSource = (source) => {
      const trimmed = (source || '').trimStart();
      return /^<!doctype html/i.test(trimmed) || /<html[\\s>]/i.test(trimmed);
    };
    const applyManagedHead = (parsed) => {
      document.head
        .querySelectorAll('[data-artifact-managed-head="true"]')
        .forEach((node) => node.remove());
      Array.from(parsed.head.children).forEach((node) => {
        const tagName = node.tagName.toLowerCase();
        if (tagName === 'meta' || tagName === 'title' || tagName === 'base') {
          return;
        }
        if (tagName === 'script') {
          return;
        }
        const clone = node.cloneNode(true);
        clone.setAttribute('data-artifact-managed-head', 'true');
        document.head.appendChild(clone);
      });
    };
    window.__applyArtifactSource__ = (rawSource) => {
      try {
        const root = document.getElementById('artifact-root');
        if (!root) {
          return 'no-root';
        }
        const source = rawSource || '';
        if (isFullDocumentSource(source)) {
          const parsed = new DOMParser().parseFromString(source, 'text/html');
          applyManagedHead(parsed);
          root.innerHTML = parsed.body ? parsed.body.innerHTML : '';
        } else {
          document.head
            .querySelectorAll('[data-artifact-managed-head="true"]')
            .forEach((node) => node.remove());
          root.innerHTML = source;
        }
        lockScroll();
        if (window.__artifactHeight__) {
          window.__artifactHeight__();
          requestAnimationFrame(window.__artifactHeight__);
          setTimeout(window.__artifactHeight__, 50);
          setTimeout(window.__artifactHeight__, 150);
        }
        if (window.__artifactDomCommit__) {
          window.__artifactDomCommit__({
            sourceLength: source.length,
            artifactRectHeight: root.getBoundingClientRect().height
          });
        }
        return 'success';
      } catch (e) {
        return 'error:' + e.message;
      }
    };
    const decodeArtifactPayload = (base64Payload) => {
      const binary = atob(base64Payload || '');
      const bytes = Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
      if (typeof TextDecoder !== 'undefined') {
        return new TextDecoder().decode(bytes);
      }
      let percentEncoded = '';
      bytes.forEach((value) => {
        percentEncoded += '%' + value.toString(16).padStart(2, '0');
      });
      return decodeURIComponent(percentEncoded);
    };
    window.__applyArtifactPayload__ = (base64Payload) => {
      try {
        return window.__applyArtifactSource__(decodeArtifactPayload(base64Payload));
      } catch (e) {
        return 'error:' + e.message;
      }
    };
    const postHeight = () => {
      const body = document.body;
      const root = document.documentElement;
      const artifactRoot = document.getElementById('artifact-root');
      const artifactRectHeight = artifactRoot
        ? artifactRoot.getBoundingClientRect().height
        : 0;
      const payload = {
        event: 'height_measure',
        artifactRectHeight,
        bodyScrollHeight: body ? body.scrollHeight : 0,
        bodyOffsetHeight: body ? body.offsetHeight : 0,
        rootScrollHeight: root ? root.scrollHeight : 0,
        rootOffsetHeight: root ? root.offsetHeight : 0
      };
      const height = Math.max(
        payload.bodyScrollHeight,
        payload.bodyOffsetHeight,
        payload.rootScrollHeight,
        payload.rootOffsetHeight
      );
      if (window.ArtifactHeight && typeof window.ArtifactHeight.postMessage === 'function') {
        window.ArtifactHeight.postMessage(JSON.stringify({
          ...payload,
          height
        }));
      }
    };
    window.__artifactDomCommit__ = (meta) => {
      if (window.ArtifactRenderState &&
          typeof window.ArtifactRenderState.postMessage === 'function') {
        window.ArtifactRenderState.postMessage(JSON.stringify({
          event: 'dom_commit',
          sourceLength: meta && meta.sourceLength,
          artifactRectHeight: meta && meta.artifactRectHeight
        }));
      }
    };
    window.__artifactLockScroll__ = lockScroll;
    window.__artifactHeight__ = postHeight;
    lockScroll();
    window.addEventListener('load', () => {
      lockScroll();
      postHeight();
      requestAnimationFrame(postHeight);
      setTimeout(postHeight, 120);
      setTimeout(postHeight, 360);
    });
    window.addEventListener('resize', () => {
      lockScroll();
      postHeight();
    });
    if (typeof ResizeObserver !== 'undefined') {
      const observer = new ResizeObserver(() => {
        lockScroll();
        postHeight();
      });
      window.addEventListener('DOMContentLoaded', () => {
        if (document.body) observer.observe(document.body);
        if (document.documentElement) observer.observe(document.documentElement);
        lockScroll();
        postHeight();
      });
    } else {
      window.addEventListener('DOMContentLoaded', () => {
        lockScroll();
        postHeight();
      });
    }
  })();
</script>
$hostStyles
''';
  return '''
<!DOCTYPE html>
<html>
  <head>
    $headInjection
  </head>
  <body>
    <div id="artifact-root"></div>
  </body>
</html>
''';
}

/// Builds the final preview document by loading the complete source as a
/// browser document, with only host measurement and containment injected.
String buildFinalArtifactPreviewDocument(
  String source, {
  bool lockScroll = true,
  Map<String, String> hostCssVariables = const <String, String>{},
}) {
  final headInjection = _buildArtifactPreviewHeadInjection(
    lockScroll: lockScroll,
    hostCssVariables: hostCssVariables,
  );
  final htmlTagPattern = RegExp(r'<html[\s>]', caseSensitive: false);
  final headTagPattern = RegExp(r'<head[^>]*>', caseSensitive: false);
  final hasHtmlTag = htmlTagPattern.hasMatch(source);
  final headMatch = headTagPattern.firstMatch(source);
  if (headMatch != null) {
    final matchedHead = headMatch.group(0)!;
    return source.replaceFirst(matchedHead, '$matchedHead$headInjection');
  }
  if (hasHtmlTag) {
    final htmlMatch =
        RegExp(r'<html[^>]*>', caseSensitive: false).firstMatch(source);
    if (htmlMatch != null) {
      final matchedHtml = htmlMatch.group(0)!;
      return source.replaceFirst(
        matchedHtml,
        '$matchedHtml<head>$headInjection</head>',
      );
    }
  }
  return '''
<!DOCTYPE html>
<html>
  <head>
    $headInjection
  </head>
  <body>
    <div id="artifact-root">
      $source
    </div>
  </body>
</html>
''';
}

String _buildArtifactPreviewHeadInjection({
  required bool lockScroll,
  required Map<String, String> hostCssVariables,
}) {
  final hostStyles = buildArtifactPreviewHostStyles(hostCssVariables);
  return '''
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob: https: http:; style-src 'unsafe-inline' data: https: http:; font-src data: https: http:; script-src 'unsafe-inline' 'unsafe-eval' data: blob:; connect-src 'none'; media-src data: blob:; frame-src data: blob:; object-src 'none'; base-uri 'none'; form-action 'none'; navigate-to 'none'">
<base target="_self">
<script>
  (function() {
    const lockScroll = () => {
      if (document.documentElement) {
        document.documentElement.style.overflow = '${lockScroll ? 'hidden' : 'auto'}';
        document.documentElement.style.touchAction = '${lockScroll ? 'none' : 'auto'}';
      }
      if (document.body) {
        document.body.style.overflow = '${lockScroll ? 'hidden' : 'auto'}';
        document.body.style.touchAction = '${lockScroll ? 'none' : 'auto'}';
      }
    };
    const postHeight = () => {
      const body = document.body;
      const root = document.documentElement;
      const artifactRoot = document.getElementById('artifact-root');
      const artifactRectHeight = artifactRoot
        ? artifactRoot.getBoundingClientRect().height
        : 0;
      const payload = {
        event: 'height_measure',
        artifactRectHeight,
        bodyScrollHeight: body ? body.scrollHeight : 0,
        bodyOffsetHeight: body ? body.offsetHeight : 0,
        rootScrollHeight: root ? root.scrollHeight : 0,
        rootOffsetHeight: root ? root.offsetHeight : 0
      };
      const height = Math.max(
        payload.bodyScrollHeight,
        payload.bodyOffsetHeight,
        payload.rootScrollHeight,
        payload.rootOffsetHeight
      );
      if (window.ArtifactHeight && typeof window.ArtifactHeight.postMessage === 'function') {
        window.ArtifactHeight.postMessage(JSON.stringify({
          ...payload,
          height
        }));
      }
    };
    window.__artifactLockScroll__ = lockScroll;
    window.__artifactHeight__ = postHeight;
    lockScroll();
    window.addEventListener('load', () => {
      lockScroll();
      postHeight();
      requestAnimationFrame(postHeight);
      setTimeout(postHeight, 120);
      setTimeout(postHeight, 360);
    });
    window.addEventListener('resize', () => {
      lockScroll();
      postHeight();
    });
    if (typeof ResizeObserver !== 'undefined') {
      const observer = new ResizeObserver(() => {
        lockScroll();
        postHeight();
      });
      window.addEventListener('DOMContentLoaded', () => {
        if (document.body) observer.observe(document.body);
        if (document.documentElement) observer.observe(document.documentElement);
        lockScroll();
        postHeight();
      });
    } else {
      window.addEventListener('DOMContentLoaded', () => {
        lockScroll();
        postHeight();
      });
    }
  })();
</script>
$hostStyles
''';
}

String buildArtifactPreviewHostStyles(Map<String, String> hostCssVariables) {
  return const ArtifactHostStyleBuilder().buildStyleBlock(hostCssVariables);
}

/// Minimal native preview surface for inline artifacts.
class ArtifactPreviewSurface extends StatefulWidget {
  const ArtifactPreviewSurface({
    super.key,
    required this.artifactId,
    required this.source,
    required this.sourcePath,
    this.isRuntimePreview = false,
    this.enableInternalScroll = false,
    this.sessionRecorder,
    this.turnId,
    this.providerCallId,
  });

  final String artifactId;
  final String? source;
  final String sourcePath;
  final bool isRuntimePreview;
  final bool enableInternalScroll;
  final ArtifactRenderSessionRecorder? sessionRecorder;
  final String? turnId;
  final String? providerCallId;

  @override
  State<ArtifactPreviewSurface> createState() => _ArtifactPreviewSurfaceState();
}

class _ArtifactPreviewSurfaceState extends State<ArtifactPreviewSurface> {
  WebViewController? _controller;
  WebViewController? _pendingFinalController;
  String? _errorText;
  double _previewHeight = _defaultArtifactPreviewHeight;
  bool _isPreviewTruncated = false;

  // Fixed-rate streaming update state.
  Timer? _streamingUpdateTimer;
  bool _isStreamingUpdateInFlight = false;
  String? _pendingSource;
  String? _pendingFinalSource;
  String? _lastRenderedSource;
  String? _lastThemeSignature;
  bool _isControllerReady = false;
  Completer<void>? _controllerReadyCompleter;

  // Height update debouncing
  Timer? _heightDebounceTimer;
  double? _pendingHeight;
  bool? _pendingTruncated;
  late final ArtifactRenderSessionRecorder _sessionRecorder;
  late final String _sessionId;
  int _mountSequence = 0;
  bool _hasFinishedSession = false;
  bool _hasRenderedVisibleContent = false;
  int _lastObservedSourceLength = 0;

  @override
  void initState() {
    super.initState();
    _lastRenderedSource = null;
    _sessionRecorder = widget.sessionRecorder ?? ArtifactRenderSessionRecorder();
    _sessionId = _buildSessionId();
    _startRenderSession();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restorePreviewStateFromPageStorage();
    final nextSignature = _currentThemeSignature();
    if (_lastThemeSignature == nextSignature) {
      _controller ??= _createController();
      return;
    }
    final didThemeChange = _lastThemeSignature != null;
    _lastThemeSignature = nextSignature;
    _controller ??= _createController();
    final source = widget.source;
    if (didThemeChange && source != null && source.trim().isNotEmpty) {
      if (widget.isRuntimePreview) {
        _updateControllerContent(source);
      } else {
        _loadFinalSource(source);
      }
    }
  }

  @override
  void didUpdateWidget(covariant ArtifactPreviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.source != widget.source ||
        oldWidget.isRuntimePreview != widget.isRuntimePreview) {
      final oldLength = oldWidget.source?.length ?? 0;
      final newLength = widget.source?.length ?? 0;
      Logger.temp(
        _artifactPreviewLogTag,
        'source changed, scheduling update',
        reason: 'diagnose streaming performance',
        data: {
          'sourcePath': widget.sourcePath,
          'oldLength': oldLength,
          'newLength': newLength,
          'delta': newLength - oldLength,
        },
      );
      _recordSourceProgress(widget.source);

      final source = widget.source;
      if (source == null || source.trim().isEmpty) {
        _pendingSource = source;
        _ensureStreamingUpdateLoop();
      } else if (widget.isRuntimePreview) {
        _pendingSource = source;
        _ensureStreamingUpdateLoop();
      } else {
        _pendingSource = null;
        _streamingUpdateTimer?.cancel();
        _streamingUpdateTimer = null;
        _loadFinalSource(source);
      }
    }
  }

  void _ensureStreamingUpdateLoop() {
    _streamingUpdateTimer ??= Timer.periodic(_streamingDebounceDelay, (_) {
      _drainPendingSource();
    });
  }

  void _stopStreamingUpdateLoopIfIdle() {
    if (_pendingSource != null || _isStreamingUpdateInFlight) {
      return;
    }
    _streamingUpdateTimer?.cancel();
    _streamingUpdateTimer = null;
  }

  Future<void> _drainPendingSource() async {
    if (!mounted || _isStreamingUpdateInFlight) {
      return;
    }
    final newSource = _pendingSource;
    if (newSource == null) {
      _stopStreamingUpdateLoopIfIdle();
      return;
    }
    _pendingSource = null;

    if (newSource == _lastRenderedSource) {
      Logger.temp(
        _artifactPreviewLogTag,
        'skipped: source unchanged from last render',
        reason: 'diagnose streaming performance',
        data: {'sourcePath': widget.sourcePath},
      );
      _stopStreamingUpdateLoopIfIdle();
      return;
    }

    Logger.temp(
      _artifactPreviewLogTag,
      'executing scheduled update',
      reason: 'diagnose streaming performance',
      data: {
        'sourcePath': widget.sourcePath,
        'sourceLength': newSource.length,
        'lastRenderedLength': _lastRenderedSource?.length ?? 0,
      },
    );

    _isStreamingUpdateInFlight = true;
    try {
      if (_controller != null && newSource.isNotEmpty) {
        await _updateControllerContent(newSource);
      } else if (mounted) {
        setState(() {
          _errorText = null;
          _previewHeight = _defaultArtifactPreviewHeight;
          _isPreviewTruncated = false;
          _controller = _createController();
        });
      }
    } finally {
      _isStreamingUpdateInFlight = false;
      if (_pendingSource == null) {
        _stopStreamingUpdateLoopIfIdle();
      }
    }
  }

  Future<void> _updateControllerContent(String source) async {
    final controller = _controller;
    if (controller == null) return;
    await _applySourceToController(controller, source);
  }

  void _loadFinalSource(String source) {
    if (_lastRenderedSource == source &&
        _pendingFinalController == null &&
        !widget.isRuntimePreview) {
      return;
    }
    if (_pendingFinalSource == source && _pendingFinalController != null) {
      return;
    }
    final controller = _createFinalController(source);
    if (controller == null) {
      return;
    }
    _sessionRecorder.recordFinalControllerPrepared(
      sessionId: _sessionId,
      sourceLength: source.length,
      timestamp: DateTime.now(),
    );
    setState(() {
      _errorText = null;
      _pendingFinalSource = source;
      _pendingFinalController = controller;
    });
  }

  void _promotePendingFinalController(
    WebViewController controller,
    String source,
  ) {
    if (!mounted ||
        widget.isRuntimePreview ||
        widget.source != source ||
        _pendingFinalController != controller) {
      return;
    }
    _sessionRecorder.recordFinalTakeover(
      sessionId: _sessionId,
      sourceLength: source.length,
      timestamp: DateTime.now(),
    );
    setState(() {
      _controller = controller;
      _pendingFinalController = null;
      _pendingFinalSource = null;
      _lastRenderedSource = source;
      _isControllerReady = true;
      _hasRenderedVisibleContent = true;
      _controllerReadyCompleter?.complete();
    });
  }

  Future<void> _applySourceToController(
    WebViewController controller,
    String source,
  ) async {
    try {
      _sessionRecorder.recordRuntimeApplyStarted(
        sessionId: _sessionId,
        sourceLength: source.length,
        timestamp: DateTime.now(),
      );
      Logger.temp(
        _artifactPreviewLogTag,
        'using runtime apply path',
        reason: 'diagnose streaming performance',
        data: {
          'sourcePath': widget.sourcePath,
          'sourceLength': source.length,
          'hasRenderedSource': _lastRenderedSource != null,
        },
      );

      await _awaitControllerReady();
      final encodedPayload = base64Encode(utf8.encode(source));
      final payloadJson = jsonEncode(encodedPayload);
      final updateScript = '''
        (function() {
          try {
            if (window.__applyArtifactPayload__) {
              return window.__applyArtifactPayload__($payloadJson);
            }
            return 'no-apply-function';
          } catch (e) {
            return 'error:' + e.message;
          }
        })();
      ''';

      final result =
          await controller.runJavaScriptReturningResult(updateScript);
      _lastRenderedSource = source;
      _sessionRecorder.recordRuntimeApplyCompleted(
        sessionId: _sessionId,
        sourceLength: source.length,
        result: result.toString(),
        timestamp: DateTime.now(),
      );
      Logger.temp(
        _artifactPreviewLogTag,
        'runtime apply completed',
        reason: 'diagnose streaming performance',
        data: {
          'sourcePath': widget.sourcePath,
          'result': result.toString(),
        },
      );
    } catch (error) {
      Logger.temp(
        _artifactPreviewLogTag,
        'runtime apply exception',
        level: LogLevel.error,
        reason: 'diagnose streaming performance',
        data: {
          'sourcePath': widget.sourcePath,
          'error': error.toString(),
        },
      );
      if (mounted) {
        setState(() {
          _errorText = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    _streamingUpdateTimer?.cancel();
    _heightDebounceTimer?.cancel();
    _finishRenderSession();
    super.dispose();
  }

  WebViewController? _createController() {
    final source = widget.source;
    if (kIsWeb || source == null || source.trim().isEmpty) {
      return null;
    }

    try {
      _isControllerReady = false;
      _controllerReadyCompleter = Completer<void>();
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..enableZoom(false)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (request.url == 'about:blank') {
                return NavigationDecision.navigate;
              }
              return NavigationDecision.prevent;
            },
            onPageFinished: (_) {
              if (_isControllerReady) {
                return;
              }
              _isControllerReady = true;
              _controllerReadyCompleter?.complete();
            },
            onWebResourceError: (error) {
              if (!mounted) {
                return;
              }
              setState(() {
                _errorText = error.description;
              });
            },
          ),
        );
      if (!widget.enableInternalScroll) {
        _addArtifactHeightChannel(controller);
        _addArtifactRenderStateChannel(controller);
      }
      controller.loadHtmlString(
        widget.isRuntimePreview
            ? buildArtifactPreviewDocument(
                lockScroll: !widget.enableInternalScroll,
                hostCssVariables: _resolveHostCssVariables(),
              )
            : buildFinalArtifactPreviewDocument(
                source,
                lockScroll: !widget.enableInternalScroll,
                hostCssVariables: _resolveHostCssVariables(),
              ),
      );
      if (widget.isRuntimePreview) {
        unawaited(_applySourceToController(controller, source));
      } else {
        _lastRenderedSource = source;
      }
      return controller;
    } catch (error) {
      _errorText = '$error';
      return null;
    }
  }

  WebViewController? _createFinalController(String source) {
    if (kIsWeb || source.trim().isEmpty) {
      return null;
    }

    try {
      late final WebViewController controller;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..enableZoom(false)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (request.url == 'about:blank') {
                return NavigationDecision.navigate;
              }
              return NavigationDecision.prevent;
            },
            onPageFinished: (_) {
              _promotePendingFinalController(controller, source);
            },
            onWebResourceError: (error) {
              if (!mounted) {
                return;
              }
              setState(() {
                _errorText = error.description;
              });
            },
          ),
        );
      if (!widget.enableInternalScroll) {
        _addArtifactHeightChannel(controller);
        _addArtifactRenderStateChannel(controller);
      }
      controller.loadHtmlString(
        buildFinalArtifactPreviewDocument(
          source,
          lockScroll: !widget.enableInternalScroll,
          hostCssVariables: _resolveHostCssVariables(),
        ),
      );
      return controller;
    } catch (error) {
      _errorText = '$error';
      return null;
    }
  }

  void _addArtifactHeightChannel(WebViewController controller) {
    controller.addJavaScriptChannel(
      _artifactHeightChannelName,
      onMessageReceived: (message) {
        final payload = message.message.trim();
        if (!mounted) {
          return;
        }
        final parsed = _parseArtifactHeightPayload(payload);
        final value = parsed.height;
        if (value == null) {
          Logger.temp(
            _artifactPreviewLogTag,
            'artifact height payload parse failed',
            level: LogLevel.warning,
            reason: 'diagnose inline artifact height sync',
            data: {
              'sourcePath': widget.sourcePath,
              'payload': _truncateForLog(payload),
            },
          );
          return;
        }
        final viewportHeight = _resolveViewportHeight();
        final clampedHeight = clampArtifactPreviewHeight(
          value,
          viewportHeight: viewportHeight,
        );
        Logger.temp(
          _artifactPreviewLogTag,
          'artifact height payload received',
          reason: 'diagnose inline artifact height sync',
          data: {
            'sourcePath': widget.sourcePath,
            'rawHeight': value,
            'clampedHeight': clampedHeight,
            'previousHeight': _previewHeight,
            'viewportHeight': viewportHeight,
            'artifactRectHeight': parsed.artifactRectHeight,
            'bodyScrollHeight': parsed.bodyScrollHeight,
            'bodyOffsetHeight': parsed.bodyOffsetHeight,
            'rootScrollHeight': parsed.rootScrollHeight,
            'rootOffsetHeight': parsed.rootOffsetHeight,
          },
        );

        _pendingHeight = clampedHeight;
        _pendingTruncated = value > clampedHeight;
        _sessionRecorder.recordHeightSampled(
          sessionId: _sessionId,
          rawHeight: value,
          clampedHeight: clampedHeight,
          timestamp: DateTime.now(),
        );
        _heightDebounceTimer?.cancel();
        _heightDebounceTimer = Timer(_heightUpdateDebounceDelay, () {
          if (!mounted) return;
          final nextHeight = _pendingHeight ?? _previewHeight;
          final nextTruncated = _pendingTruncated ?? _isPreviewTruncated;
          setState(() {
            _previewHeight = nextHeight;
            _isPreviewTruncated = nextTruncated;
          });
          _persistPreviewStateToPageStorage(
            previewHeight: nextHeight,
            isPreviewTruncated: nextTruncated,
          );
          _sessionRecorder.recordHeightApplied(
            sessionId: _sessionId,
            appliedHeight: nextHeight,
            isPreviewTruncated: nextTruncated,
            timestamp: DateTime.now(),
          );
          Logger.temp(
            _artifactPreviewLogTag,
            'artifact height applied',
            reason: 'diagnose inline artifact height sync',
            data: {
              'sourcePath': widget.sourcePath,
              'appliedHeight': _pendingHeight,
              'isPreviewTruncated': _pendingTruncated,
            },
          );
        });
      },
    );
  }

  void _addArtifactRenderStateChannel(WebViewController controller) {
    controller.addJavaScriptChannel(
      _artifactRenderStateChannelName,
      onMessageReceived: (message) {
        if (!mounted) {
          return;
        }
        final payload = _parseArtifactRenderStatePayload(message.message);
        if (payload == null) {
          return;
        }
        if (payload.event == 'dom_commit') {
          _hasRenderedVisibleContent = true;
          _sessionRecorder.recordDomCommit(
            sessionId: _sessionId,
            sourceLength: payload.sourceLength ?? _lastObservedSourceLength,
            artifactRectHeight: payload.artifactRectHeight,
            timestamp: DateTime.now(),
          );
        }
      },
    );
  }

  Future<void> _awaitControllerReady() async {
    if (_isControllerReady) {
      return;
    }
    final completer = _controllerReadyCompleter;
    if (completer == null) {
      return;
    }
    await completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    Logger.temp(
      _artifactPreviewLogTag,
      'build called',
      reason: 'diagnose streaming performance',
      data: {
        'sourcePath': widget.sourcePath,
        'sourceLength': source?.length ?? 0,
        'sourceHashCode': source?.hashCode ?? 0,
        'hasController': _controller != null,
      },
    );
    if (_errorText != null) {
      return _buildInfoMessage(context, 'Preview unavailable\n$_errorText');
    }
    if (source == null || source.trim().isEmpty) {
      if (widget.isRuntimePreview) {
        return _buildPreviewShell(context, isRunning: true);
      }
      return _buildInfoMessage(
        context,
        'Preview unavailable\n${widget.sourcePath}',
      );
    }
    if (_controller == null) {
      return _buildPreviewShell(context, isRunning: true);
    }

    final isUpdating = _pendingSource != null ||
        _isStreamingUpdateInFlight ||
        _pendingFinalController != null;
    final showWaitingShell = !_hasRenderedVisibleContent;
    if (widget.enableInternalScroll) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            if (!showWaitingShell)
              Positioned.fill(
                child: RepaintBoundary(
                  child: WebViewWidget(
                    controller: _controller!,
                  ),
                ),
              ),
            if (_pendingFinalController != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0,
                    child: RepaintBoundary(
                      child: WebViewWidget(
                        controller: _pendingFinalController!,
                      ),
                    ),
                  ),
                ),
              ),
            if (showWaitingShell)
              Positioned.fill(
                child: _buildPreviewShell(context, isRunning: true),
              )
            else if (isUpdating)
              Positioned.fill(
                child: IgnorePointer(
                  child: _buildSweepOverlay(context),
                ),
              ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SizedBox(
                height: _previewHeight,
                child: Stack(
                  children: [
                    if (!showWaitingShell)
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: WebViewWidget(
                            controller: _controller!,
                          ),
                        ),
                      ),
                    if (_pendingFinalController != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0,
                            child: RepaintBoundary(
                              child: WebViewWidget(
                                controller: _pendingFinalController!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showWaitingShell)
                      Positioned.fill(
                        child: _buildPreviewShell(context, isRunning: true),
                      ),
                  ],
                ),
              ),
              if (!showWaitingShell && isUpdating)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _buildSweepOverlay(context),
                  ),
                ),
            ],
          ),
          if (_isPreviewTruncated) _buildTruncationMessage(context),
        ],
      ),
    );
  }

  double _resolveViewportHeight() {
    final mediaQuery = MediaQuery.maybeOf(context);
    final viewportHeight = mediaQuery?.size.height;
    if (viewportHeight == null ||
        !viewportHeight.isFinite ||
        viewportHeight <= 0) {
      return _defaultArtifactPreviewHeight;
    }
    return viewportHeight;
  }

  void _restorePreviewStateFromPageStorage() {
    final snapshot = readArtifactPreviewPageStorageSnapshot(
      context: context,
      artifactId: widget.artifactId,
    );
    final resolved = resolveArtifactPreviewVisualState(
      cachedSnapshot: snapshot,
      defaultPreviewHeight: _defaultArtifactPreviewHeight,
    );
    if (_previewHeight == resolved.previewHeight &&
        _isPreviewTruncated == resolved.isPreviewTruncated) {
      return;
    }
    _previewHeight = resolved.previewHeight;
    _isPreviewTruncated = resolved.isPreviewTruncated;
  }

  void _persistPreviewStateToPageStorage({
    required double previewHeight,
    required bool isPreviewTruncated,
  }) {
    writeArtifactPreviewPageStorageSnapshot(
      context: context,
      artifactId: widget.artifactId,
      snapshot: ArtifactPreviewPageStorageSnapshot(
        previewHeight: previewHeight,
        isPreviewTruncated: isPreviewTruncated,
      ),
    );
  }

  Map<String, String> _resolveHostCssVariables() {
    final spec = Theme.of(context).extension<AppThemeSpec>();
    if (spec == null) {
      return const <String, String>{};
    }
    return ArtifactThemeTokenMapper.fromSpec(spec);
  }

  String _currentThemeSignature() {
    final variables = _resolveHostCssVariables();
    final entries = variables.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((entry) => '${entry.key}=${entry.value}').join(';');
  }

  Widget _buildSweepOverlay(BuildContext context) {
    return RunningSweepSurface(
      isRunning: true,
      showBorder: false,
      sweepOpacity: 0.58,
      duration: const Duration(milliseconds: 1400),
      sweepAngle: math.pi / 4,
      travelDirection: AxisDirection.left,
      borderRadius: BorderRadius.circular(12),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildInfoMessage(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildTruncationMessage(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Text(
        artifactPreviewTruncationMessage,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildPreviewShell(
    BuildContext context, {
    required bool isRunning,
  }) {
    final theme = Theme.of(context);
    return Container(
      key: const Key(_artifactPreviewSweepShellKey),
      width: double.infinity,
      height: _previewHeight,
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: isRunning ? _buildSweepOverlay(context) : const SizedBox.shrink(),
    );
  }

  String _buildSessionId() {
    final turnId = widget.turnId?.trim();
    final providerCallId = widget.providerCallId?.trim();
    final turnToken = (turnId == null || turnId.isEmpty) ? 'artifact' : turnId;
    final providerToken = (providerCallId == null || providerCallId.isEmpty)
        ? widget.artifactId
        : providerCallId;
    _mountSequence += 1;
    return '$turnToken:${widget.artifactId}:$providerToken:${_mountSequence - 1}';
  }

  void _startRenderSession() {
    _sessionRecorder.startSession(
      sessionId: _sessionId,
      turnId: widget.turnId?.trim().isNotEmpty == true
          ? widget.turnId!.trim()
          : widget.artifactId,
      artifactId: widget.artifactId,
      providerCallId: widget.providerCallId?.trim(),
      sourcePath: widget.sourcePath,
      phase: widget.isRuntimePreview
          ? ArtifactRenderPhase.runtime
          : ArtifactRenderPhase.finalTakeover,
      isRuntimePreview: widget.isRuntimePreview,
      timestamp: DateTime.now(),
    );
    _recordSourceProgress(widget.source);
  }

  void _recordSourceProgress(String? source) {
    final length = source?.length ?? 0;
    if (length <= _lastObservedSourceLength) {
      return;
    }
    final delta = length - _lastObservedSourceLength;
    _lastObservedSourceLength = length;
    _sessionRecorder.recordSourceProgressed(
      sessionId: _sessionId,
      sourceLength: length,
      deltaLength: delta,
      timestamp: DateTime.now(),
    );
  }

  void _finishRenderSession() {
    if (_hasFinishedSession) {
      return;
    }
    _hasFinishedSession = true;
    try {
      _sessionRecorder.finishSession(
        sessionId: _sessionId,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      // Session may remain unused in some test-only empty-source paths.
    }
  }
}

class _ArtifactHeightPayload {
  final double? height;
  final double? artifactRectHeight;
  final double? bodyScrollHeight;
  final double? bodyOffsetHeight;
  final double? rootScrollHeight;
  final double? rootOffsetHeight;

  const _ArtifactHeightPayload({
    required this.height,
    this.artifactRectHeight,
    this.bodyScrollHeight,
    this.bodyOffsetHeight,
    this.rootScrollHeight,
    this.rootOffsetHeight,
  });
}

_ArtifactHeightPayload _parseArtifactHeightPayload(String rawPayload) {
  final directValue = double.tryParse(rawPayload);
  if (directValue != null) {
    return _ArtifactHeightPayload(height: directValue);
  }

  try {
    final decoded = jsonDecode(rawPayload);
    if (decoded is! Map<String, dynamic>) {
      return const _ArtifactHeightPayload(height: null);
    }
    return _ArtifactHeightPayload(
      height: _toDouble(decoded['height']),
      artifactRectHeight: _toDouble(decoded['artifactRectHeight']),
      bodyScrollHeight: _toDouble(decoded['bodyScrollHeight']),
      bodyOffsetHeight: _toDouble(decoded['bodyOffsetHeight']),
      rootScrollHeight: _toDouble(decoded['rootScrollHeight']),
      rootOffsetHeight: _toDouble(decoded['rootOffsetHeight']),
    );
  } catch (_) {
    return const _ArtifactHeightPayload(height: null);
  }
}

double? _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

String _truncateForLog(String text, {int maxLength = 240}) {
  if (text.length <= maxLength) {
    return text;
  }
  return '${text.substring(0, maxLength)}...';
}

_ArtifactRenderStatePayload? _parseArtifactRenderStatePayload(String rawPayload) {
  try {
    final decoded = jsonDecode(rawPayload);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final event = decoded['event'];
    if (event is! String || event.trim().isEmpty) {
      return null;
    }
    return _ArtifactRenderStatePayload(
      event: event,
      sourceLength: decoded['sourceLength'] is num
          ? (decoded['sourceLength'] as num).toInt()
          : int.tryParse('${decoded['sourceLength']}'),
      artifactRectHeight: _toDouble(decoded['artifactRectHeight']),
    );
  } catch (_) {
    return null;
  }
}

class _ArtifactRenderStatePayload {
  const _ArtifactRenderStatePayload({
    required this.event,
    this.sourceLength,
    this.artifactRectHeight,
  });

  final String event;
  final int? sourceLength;
  final double? artifactRectHeight;
}
