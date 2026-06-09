import 'dart:async';
import 'dart:convert';
import 'package:ai_chat/models/artifact/artifact_render_session_snapshot.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/services/artifact/artifact_render_session_recorder.dart';
import 'package:ai_chat/services/artifact/artifact_host_style_builder.dart';
import 'package:ai_chat/services/debug/streaming_visibility_reporter.dart';
import 'package:ai_chat/services/artifact/artifact_theme_token_mapper.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_page_storage.dart';
import 'package:ai_chat/widgets/tool_renderers/tool_running_effects.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
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

enum ArtifactMeasuredHeightBasis {
  reported,
  artifactRect,
  body,
  rootOffset,
  rootScroll,
}

class ArtifactMeasuredHeightResolution {
  const ArtifactMeasuredHeightResolution({
    required this.height,
    required this.basis,
  });

  final double height;
  final ArtifactMeasuredHeightBasis basis;
}

class ArtifactHostViewportMetrics {
  const ArtifactHostViewportMetrics({
    required this.configuredPreviewHeight,
    required this.renderHeight,
    required this.overshootPx,
    required this.gapFromMeasuredHeightPx,
    required this.gapFromClampedHeightPx,
  });

  final double configuredPreviewHeight;
  final double renderHeight;
  final double overshootPx;
  final double? gapFromMeasuredHeightPx;
  final double? gapFromClampedHeightPx;
}

@visibleForTesting
bool shouldPrepareFinalArtifactTakeover({
  required String source,
  required String? lastRenderedSource,
  required String? pendingFinalSource,
  required bool hasPendingFinalController,
  required bool isRuntimePreview,
  required bool previousWasRuntimePreview,
}) {
  if (isRuntimePreview) {
    return false;
  }
  if (pendingFinalSource == source && hasPendingFinalController) {
    return false;
  }
  if (previousWasRuntimePreview) {
    return true;
  }
  return lastRenderedSource != source || hasPendingFinalController;
}

@visibleForTesting
bool shouldReloadArtifactHostDocumentForThemeChange({
  required String? source,
}) {
  return source != null && source.trim().isNotEmpty;
}

enum ArtifactHostViewportProbeStatus {
  ok,
  noContext,
  noRenderObject,
  nonRenderBox,
  noSize,
  invalidHeight,
}

extension ArtifactHostViewportProbeStatusWireName
    on ArtifactHostViewportProbeStatus {
  String get wireName {
    switch (this) {
      case ArtifactHostViewportProbeStatus.ok:
        return 'ok';
      case ArtifactHostViewportProbeStatus.noContext:
        return 'no_context';
      case ArtifactHostViewportProbeStatus.noRenderObject:
        return 'no_render_object';
      case ArtifactHostViewportProbeStatus.nonRenderBox:
        return 'non_render_box';
      case ArtifactHostViewportProbeStatus.noSize:
        return 'no_size';
      case ArtifactHostViewportProbeStatus.invalidHeight:
        return 'invalid_height';
    }
  }
}

class ArtifactHostViewportProbeSample {
  const ArtifactHostViewportProbeSample({
    required this.status,
    required this.renderHeight,
  });

  final ArtifactHostViewportProbeStatus status;
  final double? renderHeight;
}

@visibleForTesting
ArtifactHostViewportProbeStatus resolveArtifactHostViewportProbeStatus({
  required bool hasContext,
  required bool hasRenderObject,
  required bool isRenderBox,
  required bool hasSize,
  required double? renderHeight,
}) {
  if (!hasContext) {
    return ArtifactHostViewportProbeStatus.noContext;
  }
  if (!hasRenderObject) {
    return ArtifactHostViewportProbeStatus.noRenderObject;
  }
  if (!isRenderBox) {
    return ArtifactHostViewportProbeStatus.nonRenderBox;
  }
  if (!hasSize) {
    return ArtifactHostViewportProbeStatus.noSize;
  }
  if (_normalizePositiveHeight(renderHeight) == null) {
    return ArtifactHostViewportProbeStatus.invalidHeight;
  }
  return ArtifactHostViewportProbeStatus.ok;
}

@visibleForTesting
ArtifactMeasuredHeightResolution? resolveArtifactMeasuredHeight({
  required double? reportedHeight,
  double? artifactRectHeight,
  double? bodyScrollHeight,
  double? bodyOffsetHeight,
  double? rootScrollHeight,
  double? rootOffsetHeight,
}) {
  final hasStructuredMetrics = artifactRectHeight != null ||
      bodyScrollHeight != null ||
      bodyOffsetHeight != null ||
      rootScrollHeight != null ||
      rootOffsetHeight != null;

  final artifactRect = _normalizePositiveHeight(
    artifactRectHeight,
    roundUp: true,
  );
  if (artifactRect != null) {
    return ArtifactMeasuredHeightResolution(
      height: artifactRect,
      basis: ArtifactMeasuredHeightBasis.artifactRect,
    );
  }

  final bodyHeight = _maxNormalizedPositiveHeight(
    bodyScrollHeight,
    bodyOffsetHeight,
  );
  if (bodyHeight != null) {
    return ArtifactMeasuredHeightResolution(
      height: bodyHeight,
      basis: ArtifactMeasuredHeightBasis.body,
    );
  }

  final rootOffset = _normalizePositiveHeight(rootOffsetHeight);
  if (rootOffset != null) {
    return ArtifactMeasuredHeightResolution(
      height: rootOffset,
      basis: ArtifactMeasuredHeightBasis.rootOffset,
    );
  }

  final rootScroll = _normalizePositiveHeight(rootScrollHeight);
  if (rootScroll != null) {
    return ArtifactMeasuredHeightResolution(
      height: rootScroll,
      basis: ArtifactMeasuredHeightBasis.rootScroll,
    );
  }

  final reported = _normalizePositiveHeight(reportedHeight);
  if (reported != null || !hasStructuredMetrics) {
    if (reported == null) {
      return null;
    }
    return ArtifactMeasuredHeightResolution(
      height: reported,
      basis: ArtifactMeasuredHeightBasis.reported,
    );
  }

  return null;
}

@visibleForTesting
ArtifactHostViewportMetrics? resolveArtifactHostViewportMetrics({
  required double configuredPreviewHeight,
  required double? hostRenderHeight,
  required double? measuredHeight,
  required double? clampedHeight,
}) {
  final renderHeight = _normalizePositiveHeight(hostRenderHeight);
  if (renderHeight == null) {
    return null;
  }
  final configuredHeight =
      _normalizePositiveHeight(configuredPreviewHeight) ?? renderHeight;
  final normalizedMeasuredHeight = _normalizePositiveHeight(measuredHeight);
  final normalizedClampedHeight = _normalizePositiveHeight(clampedHeight);
  return ArtifactHostViewportMetrics(
    configuredPreviewHeight: configuredHeight,
    renderHeight: renderHeight,
    overshootPx: (renderHeight - configuredHeight).clamp(0.0, double.infinity),
    gapFromMeasuredHeightPx: normalizedMeasuredHeight == null
        ? null
        : (renderHeight - normalizedMeasuredHeight).clamp(0.0, double.infinity),
    gapFromClampedHeightPx: normalizedClampedHeight == null
        ? null
        : (renderHeight - normalizedClampedHeight).clamp(0.0, double.infinity),
  );
}

double? _normalizePositiveHeight(
  double? value, {
  bool roundUp = false,
}) {
  if (value == null || !value.isFinite || value <= 0) {
    return null;
  }
  return roundUp ? value.ceilToDouble() : value;
}

double? _maxNormalizedPositiveHeight(double? first, double? second) {
  final a = _normalizePositiveHeight(first);
  final b = _normalizePositiveHeight(second);
  if (a == null) {
    return b;
  }
  if (b == null) {
    return a;
  }
  return a > b ? a : b;
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
      const artifactOffsetHeight = artifactRoot ? artifactRoot.offsetHeight : 0;
      const artifactScrollHeight = artifactRoot ? artifactRoot.scrollHeight : 0;
      const artifactClientHeight = artifactRoot ? artifactRoot.clientHeight : 0;
      const bodyHeight = Math.max(
        body ? body.scrollHeight : 0,
        body ? body.offsetHeight : 0
      );
      const payload = {
        event: 'height_measure',
        artifactRectHeight,
        artifactOffsetHeight,
        artifactScrollHeight,
        artifactClientHeight,
        bodyScrollHeight: body ? body.scrollHeight : 0,
        bodyOffsetHeight: body ? body.offsetHeight : 0,
        bodyClientHeight: body ? body.clientHeight : 0,
        rootScrollHeight: root ? root.scrollHeight : 0,
        rootOffsetHeight: root ? root.offsetHeight : 0,
        rootClientHeight: root ? root.clientHeight : 0
      };
      let height = 0;
      let heightBasis = 'none';
      if (artifactRectHeight > 0) {
        height = Math.ceil(artifactRectHeight);
        heightBasis = 'artifactRect';
      } else if (bodyHeight > 0) {
        height = bodyHeight;
        heightBasis = 'body';
      } else if (payload.rootOffsetHeight > 0) {
        height = payload.rootOffsetHeight;
        heightBasis = 'rootOffset';
      } else if (payload.rootScrollHeight > 0) {
        height = payload.rootScrollHeight;
        heightBasis = 'rootScroll';
      }
      if (window.ArtifactHeight && typeof window.ArtifactHeight.postMessage === 'function') {
        window.ArtifactHeight.postMessage(JSON.stringify({
          ...payload,
          height,
          heightBasis
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
      const artifactOffsetHeight = artifactRoot ? artifactRoot.offsetHeight : 0;
      const artifactScrollHeight = artifactRoot ? artifactRoot.scrollHeight : 0;
      const artifactClientHeight = artifactRoot ? artifactRoot.clientHeight : 0;
      const bodyHeight = Math.max(
        body ? body.scrollHeight : 0,
        body ? body.offsetHeight : 0
      );
      const payload = {
        event: 'height_measure',
        artifactRectHeight,
        artifactOffsetHeight,
        artifactScrollHeight,
        artifactClientHeight,
        bodyScrollHeight: body ? body.scrollHeight : 0,
        bodyOffsetHeight: body ? body.offsetHeight : 0,
        bodyClientHeight: body ? body.clientHeight : 0,
        rootScrollHeight: root ? root.scrollHeight : 0,
        rootOffsetHeight: root ? root.offsetHeight : 0,
        rootClientHeight: root ? root.clientHeight : 0
      };
      let height = 0;
      let heightBasis = 'none';
      if (artifactRectHeight > 0) {
        height = Math.ceil(artifactRectHeight);
        heightBasis = 'artifactRect';
      } else if (bodyHeight > 0) {
        height = bodyHeight;
        heightBasis = 'body';
      } else if (payload.rootOffsetHeight > 0) {
        height = payload.rootOffsetHeight;
        heightBasis = 'rootOffset';
      } else if (payload.rootScrollHeight > 0) {
        height = payload.rootScrollHeight;
        heightBasis = 'rootScroll';
      }
      if (window.ArtifactHeight && typeof window.ArtifactHeight.postMessage === 'function') {
        window.ArtifactHeight.postMessage(JSON.stringify({
          ...payload,
          height,
          heightBasis
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
  final GlobalKey _previewViewportKey = GlobalKey(
    debugLabel: 'artifactPreviewViewport',
  );
  final Expando<String> _controllerDebugIds = Expando<String>(
    'artifactPreviewControllerId',
  );
  final Expando<String> _controllerDebugOrigins = Expando<String>(
    'artifactPreviewControllerOrigin',
  );
  final Expando<String> _controllerDebugSourcePaths = Expando<String>(
    'artifactPreviewControllerSourcePath',
  );

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
  late final StreamingVisibilityReporter _streamingVisibilityReporter;
  late final String _flowId;
  late final String _sessionId;
  bool _hasFinishedSession = false;
  bool _hasRenderedVisibleContent = false;
  int _lastObservedSourceLength = 0;
  int _controllerOrdinal = 0;
  bool _previousWidgetWasRuntimePreview = false;

  @override
  void initState() {
    super.initState();
    _lastRenderedSource = null;
    _sessionRecorder =
        widget.sessionRecorder ?? ArtifactRenderSessionRecorder();
    _streamingVisibilityReporter = const StreamingVisibilityReporter();
    _flowId = _buildFlowId();
    _sessionId = _buildSurfaceSessionId(_flowId);
    _startRenderSession();
    _recordSurfaceLifecycle('initState');
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
    if (didThemeChange &&
        shouldReloadArtifactHostDocumentForThemeChange(source: source)) {
      _reloadHostDocumentForThemeChange(source!);
    }
  }

  @override
  void didUpdateWidget(covariant ArtifactPreviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _previousWidgetWasRuntimePreview = oldWidget.isRuntimePreview;
    _recordSurfaceLifecycle(
      'didUpdateWidget',
      data: <String, dynamic>{
        'oldArtifactId': oldWidget.artifactId,
        'newArtifactId': widget.artifactId,
        'oldSourcePath': oldWidget.sourcePath,
        'newSourcePath': widget.sourcePath,
        'oldSourceLength': oldWidget.source?.length ?? 0,
        'newSourceLength': widget.source?.length ?? 0,
        'oldIsRuntimePreview': oldWidget.isRuntimePreview,
        'newIsRuntimePreview': widget.isRuntimePreview,
      },
    );

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

  void _reloadHostDocumentForThemeChange(String source) {
    _streamingUpdateTimer?.cancel();
    _streamingUpdateTimer = null;
    _pendingSource = null;
    _pendingFinalController = null;
    _pendingFinalSource = null;
    _lastRenderedSource = null;
    _isControllerReady = false;
    _controllerReadyCompleter = null;
    _errorText = null;
    _previewHeight = _defaultArtifactPreviewHeight;
    _isPreviewTruncated = false;
    _controller = _createController();
    if (mounted) {
      setState(() {});
    }
  }

  void _loadFinalSource(String source) {
    if (!shouldPrepareFinalArtifactTakeover(
      source: source,
      lastRenderedSource: _lastRenderedSource,
      pendingFinalSource: _pendingFinalSource,
      hasPendingFinalController: _pendingFinalController != null,
      isRuntimePreview: widget.isRuntimePreview,
      previousWasRuntimePreview: _previousWidgetWasRuntimePreview,
    )) {
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
      _controllerReadyCompleter?.complete();
    });
    _markVisibleContentReady();
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
      if (widget.enableInternalScroll && source.trim().isNotEmpty) {
        _markVisibleContentReady();
      }
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
    _recordSurfaceLifecycle(
      'dispose',
      data: <String, dynamic>{
        'hasRenderedVisibleContent': _hasRenderedVisibleContent,
      },
    );
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
              if (!widget.isRuntimePreview &&
                  widget.source != null &&
                  widget.source!.trim().isNotEmpty) {
                _markVisibleContentReady();
              }
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
      _registerControllerDebugMetadata(
        controller,
        origin: widget.isRuntimePreview ? 'runtime_host' : 'initial_final',
        sourcePath: widget.sourcePath,
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
      _registerControllerDebugMetadata(
        controller,
        origin: 'final_preload',
        sourcePath: widget.sourcePath,
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
        final measured = resolveArtifactMeasuredHeight(
          reportedHeight: parsed.height,
          artifactRectHeight: parsed.artifactRectHeight,
          bodyScrollHeight: parsed.bodyScrollHeight,
          bodyOffsetHeight: parsed.bodyOffsetHeight,
          rootScrollHeight: parsed.rootScrollHeight,
          rootOffsetHeight: parsed.rootOffsetHeight,
        );
        final value = measured?.height;
        if (value == null || measured == null) {
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
        final sampleContext = _buildHeightSampleContext(
          controller,
          parsed,
          sampledHeight: value,
          clampedHeight: clampedHeight,
          resolvedHeightBasis: parsed.heightBasis ?? measured.basis.name,
        );
        Logger.temp(
          _artifactPreviewLogTag,
          'artifact height payload received',
          reason: 'diagnose inline artifact height sync',
          data: {
            'sourcePath': widget.sourcePath,
            'reportedHeight': parsed.height,
            'rawHeight': value,
            'clampedHeight': clampedHeight,
            'previousHeight': _previewHeight,
            'viewportHeight': viewportHeight,
            ...sampleContext,
          },
        );

        _pendingHeight = clampedHeight;
        _pendingTruncated = value > clampedHeight;
        _sessionRecorder.recordHeightSampled(
          sessionId: _sessionId,
          rawHeight: value,
          clampedHeight: clampedHeight,
          timestamp: DateTime.now(),
          context: sampleContext,
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
          _markVisibleContentReady();
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

  void _markVisibleContentReady() {
    if (!mounted || _hasRenderedVisibleContent) {
      return;
    }
    setState(() {
      _hasRenderedVisibleContent = true;
    });
    _reportStreamingVisibility();
  }

  void _reportStreamingVisibility() {
    final turnId = widget.turnId?.trim();
    if (turnId == null || turnId.isEmpty) {
      return;
    }
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final recorder = container.read(streamingTraceRecorderProvider.notifier);
      _streamingVisibilityReporter.recordArtifactPreviewFirstVisible(
        recorder: recorder,
        turnId: turnId,
        artifactId: widget.artifactId,
        sourcePath: widget.sourcePath,
        isRuntimePreview: widget.isRuntimePreview,
        sourceLength: widget.source?.length ?? _lastObservedSourceLength,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      // Provider scope is optional in focused widget tests and debug surfaces.
    }
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

    final isUpdating = widget.isRuntimePreview ||
        _pendingSource != null ||
        _isStreamingUpdateInFlight ||
        _pendingFinalController != null;
    final showWaitingShell = !_hasRenderedVisibleContent;
    if (widget.enableInternalScroll) {
      return ClipRRect(
        key: _previewViewportKey,
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
                key: _previewViewportKey,
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
    final spec = Theme.of(context).extension<AppThemeSpec>();
    final shellSurface = spec?.structuredSurface ??
        Theme.of(context).colorScheme.surfaceContainerHighest;
    return RunningSweepSurface(
      isRunning: true,
      showBorder: false,
      sweepOpacity: kRunningCardSweepOpacity,
      duration: kRunningCardSweepDuration,
      sweepAngle: kRunningCardSweepAngle,
      travelDirection: AxisDirection.right,
      borderRadius: BorderRadius.circular(12),
      sweepColor: kRunningCardSweepColor,
      activeSweepFraction: 1.0,
      usePreciseChildExtent: true,
      widthFactor: kRunningCardSweepWidthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: shellSurface.withValues(alpha: 0.08),
        ),
        child: const SizedBox.expand(),
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

  Widget _buildPreviewShell(
    BuildContext context, {
    required bool isRunning,
  }) {
    final theme = Theme.of(context);
    final spec = theme.extension<AppThemeSpec>();
    final shellSurface = Color.lerp(
      spec?.structuredSurface ?? theme.colorScheme.surfaceContainerHigh,
      spec?.toolOutcomeSurface ?? theme.colorScheme.surfaceContainerHighest,
      0.28,
    )!
        .withValues(alpha: 0.97);
    final borderColor = spec?.divider ?? theme.colorScheme.outlineVariant;
    return Container(
      key: const Key(_artifactPreviewSweepShellKey),
      width: double.infinity,
      height: _previewHeight,
      decoration: BoxDecoration(
        color: shellSurface,
        border: Border.all(
          color: borderColor.withValues(alpha: 0.9),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: isRunning ? _buildSweepOverlay(context) : const SizedBox.shrink(),
    );
  }

  String _buildFlowId() {
    final turnId = widget.turnId?.trim();
    final providerCallId = widget.providerCallId?.trim();
    final turnToken = (turnId == null || turnId.isEmpty) ? 'artifact' : turnId;
    final providerToken = (providerCallId == null || providerCallId.isEmpty)
        ? widget.artifactId
        : providerCallId;
    return '$turnToken:${widget.artifactId}:$providerToken';
  }

  String _buildSurfaceSessionId(String flowId) {
    final uniqueSuffix = DateTime.now().microsecondsSinceEpoch.toString();
    return '$flowId:$uniqueSuffix:${shortHash(this)}';
  }

  void _startRenderSession() {
    _sessionRecorder.startSession(
      sessionId: _sessionId,
      flowId: _flowId,
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

  void _recordSurfaceLifecycle(
    String event, {
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    _sessionRecorder.recordSurfaceLifecycle(
      sessionId: _sessionId,
      event: event,
      timestamp: DateTime.now(),
      data: <String, dynamic>{
        'flowId': _flowId,
        'artifactId': widget.artifactId,
        'providerCallId': widget.providerCallId?.trim(),
        'sourcePath': widget.sourcePath,
        'isRuntimePreview': widget.isRuntimePreview,
        'sourceLength': widget.source?.length ?? 0,
        'hasRenderedVisibleContent': _hasRenderedVisibleContent,
        ...data,
      },
    );
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

  void _registerControllerDebugMetadata(
    WebViewController controller, {
    required String origin,
    required String sourcePath,
  }) {
    _controllerOrdinal += 1;
    _controllerDebugIds[controller] = 'wv_${_controllerOrdinal}_$origin';
    _controllerDebugOrigins[controller] = origin;
    _controllerDebugSourcePaths[controller] = sourcePath;
  }

  String? _controllerDebugIdOf(WebViewController? controller) {
    if (controller == null) {
      return null;
    }
    return _controllerDebugIds[controller];
  }

  String? _controllerDebugOriginOf(WebViewController? controller) {
    if (controller == null) {
      return null;
    }
    return _controllerDebugOrigins[controller];
  }

  String? _controllerDebugSourcePathOf(WebViewController? controller) {
    if (controller == null) {
      return null;
    }
    return _controllerDebugSourcePaths[controller];
  }

  String _resolveControllerRole(WebViewController controller) {
    if (identical(controller, _controller)) {
      return 'active';
    }
    if (identical(controller, _pendingFinalController)) {
      return 'pendingFinal';
    }
    return 'detached';
  }

  Map<String, dynamic> _buildHeightSampleContext(
    WebViewController controller,
    _ArtifactHeightPayload payload, {
    required double sampledHeight,
    required double clampedHeight,
    required String resolvedHeightBasis,
  }) {
    final previousAppliedHeight = _previewHeight;
    final controllerSourcePath = _controllerDebugSourcePathOf(controller);
    final pendingFinalController = _pendingFinalController;
    final hostViewportProbe = _resolveHostViewportProbeSample();
    final hostViewportMetrics = resolveArtifactHostViewportMetrics(
      configuredPreviewHeight: _previewHeight,
      hostRenderHeight: hostViewportProbe.renderHeight,
      measuredHeight: sampledHeight,
      clampedHeight: clampedHeight,
    );
    return <String, dynamic>{
      'heightBasis': resolvedHeightBasis,
      'artifactRectHeight': payload.artifactRectHeight,
      'artifactOffsetHeight': payload.artifactOffsetHeight,
      'artifactScrollHeight': payload.artifactScrollHeight,
      'artifactClientHeight': payload.artifactClientHeight,
      'bodyScrollHeight': payload.bodyScrollHeight,
      'bodyOffsetHeight': payload.bodyOffsetHeight,
      'bodyClientHeight': payload.bodyClientHeight,
      'rootScrollHeight': payload.rootScrollHeight,
      'rootOffsetHeight': payload.rootOffsetHeight,
      'rootClientHeight': payload.rootClientHeight,
      'controllerId': _controllerDebugIdOf(controller),
      'controllerRole': _resolveControllerRole(controller),
      'controllerOrigin': _controllerDebugOriginOf(controller),
      'controllerSourcePath': controllerSourcePath,
      'activeControllerId': _controllerDebugIdOf(_controller),
      'activeControllerOrigin': _controllerDebugOriginOf(_controller),
      'activeControllerSourcePath': _controllerDebugSourcePathOf(_controller),
      'pendingFinalControllerId': _controllerDebugIdOf(pendingFinalController),
      'pendingFinalControllerOrigin': _controllerDebugOriginOf(
        pendingFinalController,
      ),
      'pendingFinalSourcePath': _controllerDebugSourcePathOf(
        pendingFinalController,
      ),
      'widgetSourcePath': widget.sourcePath,
      'previousAppliedHeight': previousAppliedHeight,
      'sampleDeltaFromPreviousAppliedPx':
          sampledHeight - previousAppliedHeight,
      'sampledFromPendingFinalController': identical(
        controller,
        pendingFinalController,
      ),
      'hasPendingFinalController': pendingFinalController != null,
      'hostViewportProbeStatus': hostViewportProbe.status.wireName,
      'hostViewportConfiguredHeight': hostViewportMetrics?.configuredPreviewHeight,
      'hostViewportRenderHeight': hostViewportMetrics?.renderHeight,
      'hostViewportOvershootPx': hostViewportMetrics?.overshootPx,
      'hostViewportGapFromMeasuredHeightPx':
          hostViewportMetrics?.gapFromMeasuredHeightPx,
      'hostViewportGapFromClampedHeightPx':
          hostViewportMetrics?.gapFromClampedHeightPx,
      'controllerSourcePathMismatch': controllerSourcePath != null &&
          controllerSourcePath != widget.sourcePath,
      'rootScrollOutlierPx': _resolveRootScrollOutlierPx(payload),
      'artifactRectStretchPx': _resolveArtifactRectStretchPx(payload),
    };
  }

  ArtifactHostViewportProbeSample _resolveHostViewportProbeSample() {
    final context = _previewViewportKey.currentContext;
    final renderObject = context?.findRenderObject();
    final renderBox = renderObject is RenderBox ? renderObject : null;
    final rawHeight =
        renderBox != null && renderBox.hasSize ? renderBox.size.height : null;
    final status = resolveArtifactHostViewportProbeStatus(
      hasContext: context != null,
      hasRenderObject: renderObject != null,
      isRenderBox: renderBox != null,
      hasSize: renderBox?.hasSize ?? false,
      renderHeight: rawHeight,
    );
    return ArtifactHostViewportProbeSample(
      status: status,
      renderHeight: status == ArtifactHostViewportProbeStatus.ok
          ? _normalizePositiveHeight(rawHeight)
          : null,
    );
  }
}

class _ArtifactHeightPayload {
  final double? height;
  final String? heightBasis;
  final double? artifactRectHeight;
  final double? artifactOffsetHeight;
  final double? artifactScrollHeight;
  final double? artifactClientHeight;
  final double? bodyScrollHeight;
  final double? bodyOffsetHeight;
  final double? bodyClientHeight;
  final double? rootScrollHeight;
  final double? rootOffsetHeight;
  final double? rootClientHeight;

  const _ArtifactHeightPayload({
    required this.height,
    this.heightBasis,
    this.artifactRectHeight,
    this.artifactOffsetHeight,
    this.artifactScrollHeight,
    this.artifactClientHeight,
    this.bodyScrollHeight,
    this.bodyOffsetHeight,
    this.bodyClientHeight,
    this.rootScrollHeight,
    this.rootOffsetHeight,
    this.rootClientHeight,
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
      heightBasis: decoded['heightBasis']?.toString(),
      artifactRectHeight: _toDouble(decoded['artifactRectHeight']),
      artifactOffsetHeight: _toDouble(decoded['artifactOffsetHeight']),
      artifactScrollHeight: _toDouble(decoded['artifactScrollHeight']),
      artifactClientHeight: _toDouble(decoded['artifactClientHeight']),
      bodyScrollHeight: _toDouble(decoded['bodyScrollHeight']),
      bodyOffsetHeight: _toDouble(decoded['bodyOffsetHeight']),
      bodyClientHeight: _toDouble(decoded['bodyClientHeight']),
      rootScrollHeight: _toDouble(decoded['rootScrollHeight']),
      rootOffsetHeight: _toDouble(decoded['rootOffsetHeight']),
      rootClientHeight: _toDouble(decoded['rootClientHeight']),
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

double _resolveRootScrollOutlierPx(_ArtifactHeightPayload payload) {
  final rootScrollHeight = payload.rootScrollHeight;
  if (rootScrollHeight == null || !rootScrollHeight.isFinite) {
    return 0;
  }
  final baselines = <double?>[
    payload.artifactRectHeight,
    payload.artifactOffsetHeight,
    payload.artifactScrollHeight,
    payload.artifactClientHeight,
    payload.bodyScrollHeight,
    payload.bodyOffsetHeight,
    payload.bodyClientHeight,
    payload.rootOffsetHeight,
    payload.rootClientHeight,
  ].whereType<double>().where((value) => value.isFinite && value > 0);
  var maxBaseline = 0.0;
  for (final baseline in baselines) {
    if (baseline > maxBaseline) {
      maxBaseline = baseline;
    }
  }
  final outlier = rootScrollHeight - maxBaseline;
  return outlier > 0 ? outlier : 0;
}

double _resolveArtifactRectStretchPx(_ArtifactHeightPayload payload) {
  final artifactRectHeight = payload.artifactRectHeight;
  if (artifactRectHeight == null || !artifactRectHeight.isFinite) {
    return 0;
  }
  final intrinsicHeights = <double?>[
    payload.artifactOffsetHeight,
    payload.artifactScrollHeight,
    payload.artifactClientHeight,
  ].whereType<double>().where((value) => value.isFinite && value > 0);
  var maxIntrinsicHeight = 0.0;
  for (final intrinsicHeight in intrinsicHeights) {
    if (intrinsicHeight > maxIntrinsicHeight) {
      maxIntrinsicHeight = intrinsicHeight;
    }
  }
  final stretch = artifactRectHeight - maxIntrinsicHeight;
  return stretch > 0 ? stretch : 0;
}

String _truncateForLog(String text, {int maxLength = 240}) {
  if (text.length <= maxLength) {
    return text;
  }
  return '${text.substring(0, maxLength)}...';
}

_ArtifactRenderStatePayload? _parseArtifactRenderStatePayload(
    String rawPayload) {
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
