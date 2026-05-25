import 'dart:async';

import 'package:ai_chat/services/artifact/artifact_theme_token_mapper.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const double _minArtifactPreviewHeight = 180;
const double _defaultArtifactPreviewHeight = 260;
const double _maxArtifactPreviewScreenCount = 3;
const String _artifactHeightChannelName = 'ArtifactHeight';
const String artifactPreviewTruncationMessage =
    '内容较长，长按进入详情页查看完整内容。';
const Duration _streamingDebounceDelay = Duration(seconds: 1);

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
  return rawHeight.clamp(
    _minArtifactPreviewHeight,
    maxArtifactPreviewHeight,
  ).toDouble();
}

/// Builds a constrained HTML document for native artifact preview.
String buildArtifactPreviewDocument(
  String source, {
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
    const postHeight = () => {
      const body = document.body;
      const root = document.documentElement;
      const height = Math.max(
        body ? body.scrollHeight : 0,
        body ? body.offsetHeight : 0,
        root ? root.scrollHeight : 0,
        root ? root.offsetHeight : 0
      );
      if (window.ArtifactHeight && typeof window.ArtifactHeight.postMessage === 'function') {
        window.ArtifactHeight.postMessage(String(height));
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

String buildArtifactPreviewHostStyles(Map<String, String> hostCssVariables) {
  final variableLines = hostCssVariables.entries
      .map((entry) => '        ${entry.key}: ${entry.value};')
      .join('\n');
  final rootBlock = variableLines.isEmpty
      ? ''
      : '''
      :root {
$variableLines
      }
''';
  return '''
<style>
$rootBlock
  html, body {
    margin: 0;
    padding: 0;
    background: var(--app-artifact-page-bg, #ffffff);
    color: var(--app-artifact-text-primary, #1f1f1e);
    font-family: var(--app-artifact-font-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif);
  }

  * {
    box-sizing: border-box;
  }

  #artifact-root {
    width: 100%;
    background: var(--app-artifact-page-bg, #ffffff);
    color: var(--app-artifact-text-primary, #1f1f1e);
  }
</style>
''';
}

/// Minimal native preview surface for inline artifacts.
class ArtifactPreviewSurface extends StatefulWidget {
  const ArtifactPreviewSurface({
    super.key,
    required this.source,
    required this.isStale,
    required this.sourcePath,
    this.enableInternalScroll = false,
  });

  final String? source;
  final bool isStale;
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

  // Debouncing state
  Timer? _debounceTimer;
  String? _pendingSource;
  String? _lastRenderedSource;
  String? _lastThemeSignature;

  @override
  void initState() {
    super.initState();
    _lastRenderedSource = widget.source;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextSignature = _currentThemeSignature();
    if (_lastThemeSignature == nextSignature) {
      _controller ??= _createController();
      return;
    }
    final didThemeChange = _lastThemeSignature != null;
    _lastThemeSignature = nextSignature;
    _controller ??= _createController();
    final source = widget.source;
    if (didThemeChange &&
        !widget.isStale &&
        source != null &&
        source.trim().isNotEmpty) {
      _updateControllerContent(source);
    }
  }

  @override
  void didUpdateWidget(covariant ArtifactPreviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle stale state change immediately
    if (oldWidget.isStale != widget.isStale && widget.isStale) {
      _debounceTimer?.cancel();
      _pendingSource = null;
      return;
    }

    // If source changed, debounce the update
    if (oldWidget.source != widget.source) {
      _pendingSource = widget.source;
      _debounceTimer?.cancel();

      // Use debouncing to reduce update frequency during streaming
      _debounceTimer = Timer(_streamingDebounceDelay, () {
        if (!mounted || _pendingSource == null) return;

        final newSource = _pendingSource!;
        _pendingSource = null;

        // Only update if source actually changed from last render
        if (newSource == _lastRenderedSource) return;

        _lastRenderedSource = newSource;

        // Try incremental update first, fall back to full rebuild
        if (_controller != null && newSource.isNotEmpty) {
          _updateControllerContent(newSource);
        } else {
          setState(() {
            _errorText = null;
            _previewHeight = _defaultArtifactPreviewHeight;
            _isPreviewTruncated = false;
            _controller = _createController();
          });
        }
      });
    }
  }

  void _updateControllerContent(String source) {
    final controller = _controller;
    if (controller == null) return;

    try {
      controller.loadHtmlString(
        buildArtifactPreviewDocument(
          source,
          lockScroll: !widget.enableInternalScroll,
          hostCssVariables: _resolveHostCssVariables(),
        ),
      );
      // Reset height state for new content
      if (mounted) {
        setState(() {
          _previewHeight = _defaultArtifactPreviewHeight;
          _isPreviewTruncated = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  WebViewController? _createController() {
    final source = widget.source;
    if (kIsWeb || widget.isStale || source == null || source.trim().isEmpty) {
      return null;
    }

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..enableZoom(false)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (request.url == 'about:blank') {
                return NavigationDecision.navigate;
              }
              return NavigationDecision.prevent;
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
            final value = double.tryParse(message.message.trim());
            if (value == null || !mounted) {
              return;
            }
            final viewportHeight = _resolveViewportHeight();
            final clampedHeight = clampArtifactPreviewHeight(
              value,
              viewportHeight: viewportHeight,
            );
            setState(() {
              _previewHeight = clampedHeight;
              _isPreviewTruncated = value > clampedHeight;
            });
          },
        );
      }
      controller.loadHtmlString(
        buildArtifactPreviewDocument(
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

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    if (widget.isStale) {
      return _buildInfoMessage(
        context,
        '该 artifact 已在后续回复中更新。此处保留历史引用。',
      );
    }
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
      return _buildSourceFallback(context, source);
    }

    // Show loading indicator if we have pending updates
    final isUpdating = _pendingSource != null && _pendingSource != _lastRenderedSource;
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
    if (viewportHeight == null || !viewportHeight.isFinite || viewportHeight <= 0) {
      return _defaultArtifactPreviewHeight;
    }
    return viewportHeight;
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

  Widget _buildSourceFallback(BuildContext context, String source) {
    final theme = Theme.of(context);
    final estimatedHeight = _estimateSourceFallbackHeight(source);
    final fallbackHeight = clampArtifactPreviewHeight(
      estimatedHeight,
      viewportHeight: _resolveViewportHeight(),
    );
    final isTruncated = estimatedHeight > fallbackHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: fallbackHeight),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: ClipRect(
            child: SelectableText(
              source,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'JetBrainsMono',
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        if (isTruncated) _buildTruncationMessage(context),
      ],
    );
  }

  double _estimateSourceFallbackHeight(String source) {
    final lines = '\n'.allMatches(source).length + 1;
    const estimatedLineHeight = 22.0;
    const estimatedPadding = 24.0;
    return (lines * estimatedLineHeight) + estimatedPadding;
  }
}
