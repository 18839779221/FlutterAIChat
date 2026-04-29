import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const double _minArtifactPreviewHeight = 180;
const double _maxArtifactPreviewHeight = 720;
const double _defaultArtifactPreviewHeight = 260;
const String _artifactHeightChannelName = 'ArtifactHeight';

double clampArtifactPreviewHeight(double rawHeight) {
  if (!rawHeight.isFinite) {
    return _defaultArtifactPreviewHeight;
  }
  return rawHeight.clamp(
    _minArtifactPreviewHeight,
    _maxArtifactPreviewHeight,
  ).toDouble();
}

/// Builds a constrained HTML document for native artifact preview.
String buildArtifactPreviewDocument(String source) {
  const headInjection = '''
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob: https: http:; style-src 'unsafe-inline' data: https: http:; font-src data: https: http:; script-src 'unsafe-inline' 'unsafe-eval' data: blob:; connect-src 'none'; media-src data: blob:; frame-src data: blob:; object-src 'none'; base-uri 'none'; form-action 'none'; navigate-to 'none'">
<base target="_self">
<script>
  (function() {
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
    window.__artifactHeight__ = postHeight;
    window.addEventListener('load', () => {
      postHeight();
      requestAnimationFrame(postHeight);
      setTimeout(postHeight, 120);
      setTimeout(postHeight, 360);
    });
    window.addEventListener('resize', postHeight);
    if (typeof ResizeObserver !== 'undefined') {
      const observer = new ResizeObserver(() => postHeight());
      window.addEventListener('DOMContentLoaded', () => {
        if (document.body) observer.observe(document.body);
        if (document.documentElement) observer.observe(document.documentElement);
        postHeight();
      });
    } else {
      window.addEventListener('DOMContentLoaded', postHeight);
    }
  })();
</script>
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
    <style>
      html, body {
        margin: 0;
        padding: 0;
        background: transparent;
      }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
    </style>
  </head>
  <body>
    $source
  </body>
</html>
''';
}

/// Minimal native preview surface for inline artifacts.
class ArtifactPreviewSurface extends StatefulWidget {
  const ArtifactPreviewSurface({
    super.key,
    required this.source,
    required this.isStale,
    required this.sourcePath,
  });

  final String? source;
  final bool isStale;
  final String sourcePath;

  @override
  State<ArtifactPreviewSurface> createState() => _ArtifactPreviewSurfaceState();
}

class _ArtifactPreviewSurfaceState extends State<ArtifactPreviewSurface> {
  WebViewController? _controller;
  String? _errorText;
  double _previewHeight = _defaultArtifactPreviewHeight;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(covariant ArtifactPreviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.isStale != widget.isStale) {
      _errorText = null;
      _previewHeight = _defaultArtifactPreviewHeight;
      _controller = _createController();
    }
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
        ..addJavaScriptChannel(
          _artifactHeightChannelName,
          onMessageReceived: (message) {
            final value = double.tryParse(message.message.trim());
            if (value == null || !mounted) {
              return;
            }
            setState(() {
              _previewHeight = clampArtifactPreviewHeight(value);
            });
          },
        )
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
        )
        ..loadHtmlString(buildArtifactPreviewDocument(source));
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: _previewHeight,
        color: Colors.transparent,
        child: WebViewWidget(controller: _controller!),
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

  Widget _buildSourceFallback(BuildContext context, String source) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 260),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SingleChildScrollView(
        child: SelectableText(
          source,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'JetBrainsMono',
            height: 1.45,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
