import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/services/artifact/artifact_host_style_builder.dart';
import 'package:ai_chat/services/artifact/artifact_theme_token_mapper.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_page_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const double _minArtifactPreviewHeight = 180;
const double _defaultArtifactPreviewHeight = 260;
const double _maxArtifactPreviewScreenCount = 3;
const String _artifactHeightChannelName = 'ArtifactHeight';
const String artifactPreviewTruncationMessage = '内容较长，长按进入详情页查看完整内容。';
const Duration _streamingDebounceDelay = Duration(milliseconds: 1000);
const Duration _heightUpdateDebounceDelay = Duration(milliseconds: 100);
const String _artifactPreviewLogTag = 'ArtifactPreviewSurface';

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
    this.enableInternalScroll = false,
  });

  final String artifactId;
  final String? source;
  final String sourcePath;
  final bool enableInternalScroll;

  @override
  State<ArtifactPreviewSurface> createState() => _ArtifactPreviewSurfaceState();
}

class _ArtifactPreviewSurfaceState extends State<ArtifactPreviewSurface> {
  WebViewController? _controller;
  String? _errorText;
  double _previewHeight = _defaultArtifactPreviewHeight;
  bool _isPreviewTruncated = false;

  // Fixed-rate streaming update state.
  Timer? _streamingUpdateTimer;
  bool _isStreamingUpdateInFlight = false;
  String? _pendingSource;
  String? _lastRenderedSource;
  String? _lastThemeSignature;
  bool _isControllerReady = false;
  Completer<void>? _controllerReadyCompleter;

  // Height update debouncing
  Timer? _heightDebounceTimer;
  double? _pendingHeight;
  bool? _pendingTruncated;

  @override
  void initState() {
    super.initState();
    _lastRenderedSource = null;
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
      _updateControllerContent(source);
    }
  }

  @override
  void didUpdateWidget(covariant ArtifactPreviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.source != widget.source) {
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

      _pendingSource = widget.source;
      _ensureStreamingUpdateLoop();
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

  Future<void> _applySourceToController(
    WebViewController controller,
    String source,
  ) async {
    try {
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

      final result = await controller.runJavaScriptReturningResult(updateScript);
      _lastRenderedSource = source;
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

            // Debounce height updates to avoid jitter
            _pendingHeight = clampedHeight;
            _pendingTruncated = value > clampedHeight;
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
      controller.loadHtmlString(
        buildArtifactPreviewDocument(
          lockScroll: !widget.enableInternalScroll,
          hostCssVariables: _resolveHostCssVariables(),
        ),
      );
      unawaited(_applySourceToController(controller, source));
      return controller;
    } catch (error) {
      _errorText = '$error';
      return null;
    }
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
      return _buildInfoMessage(
        context,
        'Preview unavailable\n${widget.sourcePath}',
      );
    }
    if (_controller == null) {
      return _buildPreviewPlaceholder(context);
    }

    final isUpdating = _pendingSource != null || _isStreamingUpdateInFlight;
    if (widget.enableInternalScroll) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: WebViewWidget(
                  controller: _controller!,
                ),
              ),
            ),
            if (isUpdating)
              Positioned(
                top: 8,
                right: 8,
                child: _buildStreamingIndicator(context),
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: _previewHeight,
                color: Colors.transparent,
                child: RepaintBoundary(
                  child: WebViewWidget(
                    controller: _controller!,
                  ),
                ),
              ),
              if (isUpdating)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _buildStreamingIndicator(context),
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

  Widget _buildStreamingIndicator(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '更新中',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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

  Widget _buildPreviewPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      height: _previewHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 96,
            height: 12,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            height: 10,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 10,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: 180,
            height: 10,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
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
