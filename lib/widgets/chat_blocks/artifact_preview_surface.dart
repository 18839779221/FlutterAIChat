import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:ai_chat/models/artifact/artifact_render_session_snapshot.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/services/artifact/artifact_render_session_recorder.dart';
import 'package:ai_chat/services/artifact/artifact_host_style_builder.dart';
import 'package:ai_chat/services/artifact/artifact_webview_lease_coordinator.dart';
import 'package:ai_chat/services/debug/streaming_visibility_reporter.dart';
import 'package:ai_chat/services/artifact/artifact_theme_token_mapper.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_page_storage.dart';
import 'package:ai_chat/widgets/tool_renderers/tool_running_effects.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:webview_flutter/webview_flutter.dart';

const double _minArtifactPreviewHeight = 180;
const double _defaultArtifactPreviewHeight = 260;
const String _artifactHeightChannelName = 'ArtifactHeight';
const String _artifactRenderStateChannelName = 'ArtifactRenderState';
const Duration _streamingDebounceDelay = Duration(milliseconds: 1000);
const Duration _heightUpdateDebounceDelay = Duration(milliseconds: 100);
const String _artifactPreviewLogTag = 'ArtifactPreviewSurface';
const String _artifactPreviewSweepShellKey = 'artifact-preview-sweep-shell';
const String _artifactPreviewResizeShieldKey = 'artifact-preview-resize-shield';
const int _maxRuntimeApplyRetries = 3;
const int _artifactHeightRenderProbeMaxFrames = 3;

/// Upper bound for waiting on the host document before a runtime apply.
/// Mutable so tests can shorten it; production code never reassigns it.
@visibleForTesting
Duration artifactControllerReadyTimeout = const Duration(seconds: 8);

/// How long a prepared final controller may stay un-promoted before the
/// surface falls back to reloading the final document on the active
/// controller.
@visibleForTesting
Duration artifactTakeoverFallbackDelay = const Duration(seconds: 10);

/// Delay before probing a re-attached WebView (controllerOnly → mounted).
/// iOS may have killed the suspended content process while the view was
/// off-screen; the probe detects that and triggers a full reload.
@visibleForTesting
Duration artifactLeaseReattachProbeDelay = const Duration(milliseconds: 300);

/// Upper bound for the re-attach probe JavaScript round trip.
@visibleForTesting
Duration artifactLeaseReattachProbeTimeout = const Duration(seconds: 2);

const Key artifactPreviewLeasePlaceholderKey =
    Key('artifact-preview-lease-placeholder');

void _defaultLeaseObservationSink(String event, Map<String, Object?> data) {
  Logger.temp(
    'ArtifactWebViewLease',
    event,
    reason: 'artifact webview lease coordination',
    data: Map<String, dynamic>.from(data),
  );
}

double clampArtifactPreviewHeight(
  double rawHeight, {
  required double viewportHeight,
}) {
  if (!rawHeight.isFinite) {
    return _defaultArtifactPreviewHeight;
  }
  return rawHeight
      .clamp(
        _minArtifactPreviewHeight,
        double.infinity,
      )
      .toDouble();
}

@visibleForTesting
double resolveNextArtifactPreviewHeight({
  required double currentAppliedHeight,
  required double sampledHeight,
  required bool isRuntimePreview,
}) {
  if (!isRuntimePreview) {
    return sampledHeight;
  }
  return math.max(currentAppliedHeight, sampledHeight).toDouble();
}

@visibleForTesting
bool shouldApplyArtifactHeightImmediately({
  required double currentAppliedHeight,
  required double nextResolvedHeight,
  required bool isRuntimePreview,
}) {
  return isRuntimePreview && nextResolvedHeight > currentAppliedHeight;
}

@visibleForTesting
bool shouldStartArtifactHeightRenderShield({
  required double currentAppliedHeight,
  required double nextResolvedHeight,
  required bool isRuntimePreview,
  required bool enableInternalScroll,
}) {
  return isRuntimePreview &&
      !enableInternalScroll &&
      nextResolvedHeight > currentAppliedHeight;
}

@visibleForTesting
bool shouldContinueArtifactHeightRenderProbe({
  required double configuredHeight,
  required double? renderHeight,
  required int remainingFrames,
}) {
  if (remainingFrames <= 0) {
    return false;
  }
  final normalizedRenderHeight = _normalizePositiveHeight(renderHeight);
  if (normalizedRenderHeight == null) {
    return true;
  }
  return (configuredHeight - normalizedRenderHeight).abs() > 0.5;
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

@visibleForTesting
bool shouldRebuildArtifactHostForRuntimeRestart({
  required bool isRuntimePreview,
  required bool previousWasRuntimePreview,
}) {
  return isRuntimePreview && !previousWasRuntimePreview;
}

/// Sub-resource failures (images, fonts, blocked requests) must not replace
/// the whole preview; only main-frame errors should surface. Platforms that
/// don't report the frame (`null`) are treated as main-frame to stay safe.
@visibleForTesting
bool shouldSurfaceArtifactWebResourceError({required bool? isForMainFrame}) {
  return isForMainFrame != false;
}

/// `runJavaScriptReturningResult` wraps string results in JSON quotes on
/// Android but returns them raw on iOS, so both forms must be accepted.
@visibleForTesting
bool isArtifactApplyResultSuccess(Object? rawResult) {
  if (rawResult == null) {
    return false;
  }
  var text = rawResult.toString().trim();
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    text = text.substring(1, text.length - 1);
  }
  return text == 'success';
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
          requestAnimationFrame(window.__artifactHeight__);
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
      requestAnimationFrame(postHeight);
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
    this.leaseCoordinator,
    this.turnId,
    this.providerCallId,
  });

  final String artifactId;
  final String? source;
  final String sourcePath;
  final bool isRuntimePreview;
  final bool enableInternalScroll;
  final ArtifactRenderSessionRecorder? sessionRecorder;

  /// Budget manager for live WebViews; defaults to the process-wide
  /// [ArtifactWebViewLeaseCoordinator.instance].
  final ArtifactWebViewLeaseCoordinator? leaseCoordinator;

  final String? turnId;
  final String? providerCallId;

  @override
  State<ArtifactPreviewSurface> createState() => _ArtifactPreviewSurfaceState();
}

class _ArtifactPreviewSurfaceState extends State<ArtifactPreviewSurface>
    implements ArtifactWebViewLeaseClient {
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

  // Fixed-rate streaming update state.
  Timer? _streamingUpdateTimer;
  bool _isStreamingUpdateInFlight = false;
  String? _pendingSource;
  String? _pendingFinalSource;
  String? _lastRenderedSource;
  String? _lastThemeSignature;
  bool _isControllerReady = false;
  Completer<void>? _controllerReadyCompleter;
  // Incremented whenever the active controller (or its document) is replaced;
  // in-flight applies compare generations after each await and abandon
  // silently when superseded.
  int _controllerGeneration = 0;
  int _runtimeApplyRetryCount = 0;
  bool _hasRebuiltControllerForApplyFailure = false;
  Timer? _takeoverFallbackTimer;

  // Height update debouncing
  Timer? _heightDebounceTimer;
  double? _pendingHeight;
  int _heightRenderProbeGeneration = 0;
  bool _isWaitingForHeightRenderCatchUp = false;
  late final ArtifactRenderSessionRecorder _sessionRecorder;
  late final StreamingVisibilityReporter _streamingVisibilityReporter;
  late final String _flowId;
  late final String _sessionId;
  bool _hasFinishedSession = false;
  bool _hasRenderedVisibleContent = false;
  int _lastObservedSourceLength = 0;
  int _controllerOrdinal = 0;
  bool _previousWidgetWasRuntimePreview = false;

  // WebView lease state.
  ArtifactWebViewLeaseHandle? _leaseHandle;
  bool _isResidentLease = false;
  bool _pendingThemeReload = false;
  bool _holdsStreamingPin = false;
  bool _holdsTakeoverPin = false;
  ArtifactWebViewLeaseState _lastAppliedLeaseState =
      ArtifactWebViewLeaseState.released;
  ArtifactLeaseVisibilitySample _lastLeaseSample =
      const ArtifactLeaseVisibilitySample.attached(distanceToViewportPx: 0);

  bool get _leaseAllowsWebView =>
      _leaseHandle == null ||
      _leaseHandle!.state == ArtifactWebViewLeaseState.mounted;

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
    _syncLeaseRegistration();
    final nextSignature = _currentThemeSignature();
    if (_lastThemeSignature == nextSignature) {
      if (_leaseAllowsWebView) {
        _controller ??= _createController();
      }
      return;
    }
    final didThemeChange = _lastThemeSignature != null;
    _lastThemeSignature = nextSignature;
    if (_leaseAllowsWebView) {
      _controller ??= _createController();
    }
    final source = widget.source;
    if (didThemeChange &&
        shouldReloadArtifactHostDocumentForThemeChange(source: source)) {
      if (_leaseAllowsWebView) {
        _reloadHostDocumentForThemeChange(source!);
      } else {
        // Reloading every kept-alive off-screen surface on a theme switch
        // would recreate all their documents at once; defer until regrant.
        _pendingThemeReload = true;
      }
    }
  }

  void _syncLeaseRegistration() {
    final scrollable =
        widget.enableInternalScroll ? null : Scrollable.maybeOf(context);
    _isResidentLease = widget.enableInternalScroll || scrollable == null;
    if (_leaseHandle == null) {
      final coordinator =
          widget.leaseCoordinator ?? ArtifactWebViewLeaseCoordinator.instance;
      coordinator.observationSink ??= _defaultLeaseObservationSink;
      _leaseHandle = coordinator.register(this);
      _lastAppliedLeaseState = _leaseHandle!.state;
    }
    _leaseHandle!.attachScrollPosition(
      _isResidentLease ? null : scrollable?.position,
    );
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
      if (!widget.isRuntimePreview || widget.enableInternalScroll) {
        _isWaitingForHeightRenderCatchUp = false;
      }
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
      // Each new source gets a fresh retry budget.
      _runtimeApplyRetryCount = 0;

      final source = widget.source;
      if (shouldRebuildArtifactHostForRuntimeRestart(
        isRuntimePreview: widget.isRuntimePreview,
        previousWasRuntimePreview: oldWidget.isRuntimePreview,
      )) {
        _restartRuntimePreviewHostDocument(source);
        return;
      }
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

  void _restartRuntimePreviewHostDocument(String? source) {
    _streamingUpdateTimer?.cancel();
    _streamingUpdateTimer = null;
    _takeoverFallbackTimer?.cancel();
    _takeoverFallbackTimer = null;
    _releaseTakeoverPin();
    _pendingSource = null;
    _pendingFinalController = null;
    _pendingFinalSource = null;
    _lastRenderedSource = null;
    _controllerGeneration += 1;
    _abandonControllerReadyWaiters();
    _isControllerReady = false;
    _controllerReadyCompleter = null;
    _hasRebuiltControllerForApplyFailure = false;
    _errorText = null;
    _previewHeight = _defaultArtifactPreviewHeight;
    _isWaitingForHeightRenderCatchUp = false;
    _recordSurfaceLifecycle(
      'runtime_restart_host_rebuild',
      data: <String, dynamic>{
        'sourceLength': source?.length ?? 0,
      },
    );
    if (mounted) {
      setState(() {
        _controller = _createController();
      });
    }
  }

  void _ensureStreamingUpdateLoop() {
    if (!_holdsStreamingPin && _leaseHandle != null) {
      // Active streaming must not lose its live webview to the budget.
      _holdsStreamingPin = true;
      _leaseHandle!.acquirePin();
    }
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
    _releaseStreamingPin();
  }

  Future<void> _drainPendingSource() async {
    if (!mounted || _isStreamingUpdateInFlight) {
      return;
    }
    if (!_leaseAllowsWebView) {
      // Keep the newest pending source for the regrant; ticking while the
      // webview is unmounted only burns cycles.
      _streamingUpdateTimer?.cancel();
      _streamingUpdateTimer = null;
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
    _takeoverFallbackTimer?.cancel();
    _takeoverFallbackTimer = null;
    _releaseTakeoverPin();
    _releaseStreamingPin();
    _pendingSource = null;
    _pendingFinalController = null;
    _pendingFinalSource = null;
    _lastRenderedSource = null;
    // Release any apply awaiting the old document before swapping controllers
    // so the streaming loop's in-flight flag cannot get stuck.
    _controllerGeneration += 1;
    _abandonControllerReadyWaiters();
    _isControllerReady = false;
    _controllerReadyCompleter = null;
    _runtimeApplyRetryCount = 0;
    _hasRebuiltControllerForApplyFailure = false;
    _errorText = null;
    _previewHeight = _defaultArtifactPreviewHeight;
    _isWaitingForHeightRenderCatchUp = false;
    _controller = _createController();
    if (mounted) {
      setState(() {});
    }
  }

  void _loadFinalSource(String source) {
    if (!_leaseAllowsWebView) {
      // Deferred: `_handleLeaseMountGranted` re-runs the takeover on regrant.
      return;
    }
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
    if (!_holdsTakeoverPin && _leaseHandle != null) {
      // Both controllers must stay mounted until the takeover resolves; the
      // fallback timer bounds the pin's lifetime.
      _holdsTakeoverPin = true;
      _leaseHandle!.acquirePin();
    }
    _takeoverFallbackTimer?.cancel();
    _takeoverFallbackTimer = Timer(
      artifactTakeoverFallbackDelay,
      _handleTakeoverFallback,
    );
  }

  /// Bounded recovery for a pending final controller that never promoted
  /// (onPageFinished lost, source mismatch, controller replaced): drop the
  /// hidden controller and load the final document on the active one.
  void _handleTakeoverFallback() {
    _takeoverFallbackTimer = null;
    _releaseTakeoverPin();
    if (!mounted || _pendingFinalController == null) {
      return;
    }
    final source = widget.source;
    _recordSurfaceLifecycle(
      'takeover_fallback',
      data: <String, dynamic>{
        'pendingFinalSourceLength': _pendingFinalSource?.length ?? 0,
        'currentSourceLength': source?.length ?? 0,
      },
    );
    if (widget.isRuntimePreview || source == null || source.trim().isEmpty) {
      setState(() {
        _pendingFinalController = null;
        _pendingFinalSource = null;
      });
      return;
    }
    final activeController = _controller;
    if (activeController == null) {
      _lastRenderedSource = null;
      setState(() {
        _pendingFinalController = null;
        _pendingFinalSource = null;
        _controller = _createController();
      });
      return;
    }
    _beginControllerDocumentLoad();
    activeController.loadHtmlString(
      buildFinalArtifactPreviewDocument(
        source,
        lockScroll: !widget.enableInternalScroll,
        hostCssVariables: _resolveHostCssVariables(),
      ),
    );
    _lastRenderedSource = source;
    setState(() {
      _pendingFinalController = null;
      _pendingFinalSource = null;
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
    _takeoverFallbackTimer?.cancel();
    _takeoverFallbackTimer = null;
    _releaseTakeoverPin();
    // Abandon applies still targeting the superseded runtime controller.
    _controllerGeneration += 1;
    setState(() {
      _controller = controller;
      _pendingFinalController = null;
      _pendingFinalSource = null;
      _lastRenderedSource = source;
      _markControllerReady();
    });
    _markVisibleContentReady();
  }

  Future<void> _applySourceToController(
    WebViewController controller,
    String source,
  ) async {
    final generation = _controllerGeneration;
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
      if (!mounted || generation != _controllerGeneration) {
        _recordRuntimeApplyAbandoned(generation, source);
        return;
      }
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
      if (!mounted || generation != _controllerGeneration) {
        _recordRuntimeApplyAbandoned(generation, source);
        return;
      }
      final applySucceeded = isArtifactApplyResultSuccess(result);
      if (applySucceeded) {
        _lastRenderedSource = source;
        _runtimeApplyRetryCount = 0;
      } else {
        _handleRuntimeApplyFailure(source: source, result: result.toString());
      }
      _sessionRecorder.recordRuntimeApplyCompleted(
        sessionId: _sessionId,
        sourceLength: source.length,
        result: result.toString(),
        timestamp: DateTime.now(),
      );
      if (applySucceeded &&
          widget.enableInternalScroll &&
          source.trim().isNotEmpty) {
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
      if (!mounted || generation != _controllerGeneration) {
        _recordRuntimeApplyAbandoned(generation, source);
        return;
      }
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
      setState(() {
        _errorText = '$error';
      });
    }
  }

  void _recordRuntimeApplyAbandoned(int staleGeneration, String source) {
    _recordSurfaceLifecycle(
      'runtime_apply_abandoned',
      data: <String, dynamic>{
        'staleGeneration': staleGeneration,
        'currentGeneration': _controllerGeneration,
        'abandonedSourceLength': source.length,
      },
    );
  }

  /// A failed apply must not be book-kept as rendered, otherwise the same
  /// source is skipped as "unchanged" forever. Retries go through the regular
  /// streaming loop; a broken host document gets one full controller rebuild.
  void _handleRuntimeApplyFailure({
    required String source,
    required String result,
  }) {
    _runtimeApplyRetryCount += 1;
    final isHostDocumentBroken =
        result.contains('no-root') || result.contains('no-apply-function');
    _recordSurfaceLifecycle(
      'runtime_apply_failed',
      data: <String, dynamic>{
        'result': result,
        'retryCount': _runtimeApplyRetryCount,
        'hostDocumentBroken': isHostDocumentBroken,
      },
    );
    if (_runtimeApplyRetryCount <= _maxRuntimeApplyRetries) {
      _pendingSource ??= source;
      _ensureStreamingUpdateLoop();
      return;
    }
    _runtimeApplyRetryCount = 0;
    if (isHostDocumentBroken &&
        !_hasRebuiltControllerForApplyFailure &&
        mounted) {
      _hasRebuiltControllerForApplyFailure = true;
      _recordSurfaceLifecycle('runtime_apply_controller_rebuild');
      _lastRenderedSource = null;
      setState(() {
        _controller = _createController();
      });
      return;
    }
    _recordSurfaceLifecycle(
      'runtime_apply_gave_up',
      data: <String, dynamic>{'result': result},
    );
  }

  @override
  void dispose() {
    _streamingUpdateTimer?.cancel();
    _heightDebounceTimer?.cancel();
    _takeoverFallbackTimer?.cancel();
    _leaseHandle?.unregister();
    _leaseHandle = null;
    _isWaitingForHeightRenderCatchUp = false;
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
      _beginControllerDocumentLoad();
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
              // A superseded controller (theme reload, apply-failure rebuild)
              // must not complete the ready gate of its replacement.
              if (!identical(controller, _controller) || _isControllerReady) {
                return;
              }
              _markControllerReady();
              if (!widget.isRuntimePreview &&
                  widget.source != null &&
                  widget.source!.trim().isNotEmpty) {
                _markVisibleContentReady();
              }
            },
            onWebResourceError: (error) {
              if (!identical(controller, _controller)) {
                return;
              }
              _handleWebResourceError(error);
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
              if (!identical(controller, _pendingFinalController) &&
                  !identical(controller, _controller)) {
                return;
              }
              _handleWebResourceError(error);
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

  // --- ArtifactWebViewLeaseClient ---

  @override
  String get debugLabel => '${widget.artifactId}:${widget.sourcePath}';

  @override
  bool get isResident => _isResidentLease;

  @override
  bool get allowsMountGrantNow {
    if (!mounted) {
      return false;
    }
    try {
      return !Scrollable.recommendDeferredLoadingForContext(context);
    } catch (_) {
      return true;
    }
  }

  @override
  ArtifactLeaseVisibilitySample sampleVisibility() {
    if (!mounted) {
      return const ArtifactLeaseVisibilitySample.detached();
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // Mid-frame pass (a sibling registering during build): probing the
      // render tree is not allowed here, reuse the last settled sample.
      return _lastLeaseSample;
    }
    final renderObject = context.findRenderObject();
    if (renderObject == null ||
        !renderObject.attached ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      _lastLeaseSample = const ArtifactLeaseVisibilitySample.detached();
      return _lastLeaseSample;
    }
    final scrollPosition = widget.enableInternalScroll
        ? null
        : Scrollable.maybeOf(context)?.position;
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (scrollPosition == null ||
        viewport == null ||
        !scrollPosition.hasPixels ||
        !scrollPosition.hasViewportDimension) {
      _lastLeaseSample =
          const ArtifactLeaseVisibilitySample.attached(distanceToViewportPx: 0);
      return _lastLeaseSample;
    }
    final leadingOffset = viewport.getOffsetToReveal(renderObject, 0).offset;
    final trailingOffset = leadingOffset + renderObject.size.height;
    final visibleStart = scrollPosition.pixels;
    final visibleEnd = visibleStart + scrollPosition.viewportDimension;
    double distance = 0;
    if (trailingOffset < visibleStart) {
      distance = visibleStart - trailingOffset;
    } else if (leadingOffset > visibleEnd) {
      distance = leadingOffset - visibleEnd;
    }
    _lastLeaseSample = ArtifactLeaseVisibilitySample.attached(
      distanceToViewportPx: distance,
    );
    return _lastLeaseSample;
  }

  @override
  void onLeaseStateChanged(ArtifactWebViewLeaseState state) {
    _recordSurfaceLifecycle(
      'lease_state_changed',
      data: <String, dynamic>{'leaseState': state.name},
    );
    if (!mounted) {
      return;
    }
    // The coordinator may emit this synchronously while a sibling surface is
    // registering inside its own build; rebuilding now is forbidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _applyLeaseState(_leaseHandle?.state ?? state);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _applyLeaseState(ArtifactWebViewLeaseState state) {
    final previous = _lastAppliedLeaseState;
    _lastAppliedLeaseState = state;
    setState(() {});
    switch (state) {
      case ArtifactWebViewLeaseState.mounted:
        _handleLeaseMountGranted(
          wasControllerOnly: previous == ArtifactWebViewLeaseState.controllerOnly,
        );
        break;
      case ArtifactWebViewLeaseState.controllerOnly:
        // The build branch unmounts the WebViewWidget; the controller and its
        // loaded document stay alive for a cheap re-attach.
        break;
      case ArtifactWebViewLeaseState.released:
        _releaseControllerResources();
        break;
    }
  }

  void _handleLeaseMountGranted({required bool wasControllerOnly}) {
    final source = widget.source;
    if (_pendingThemeReload) {
      _pendingThemeReload = false;
      if (shouldReloadArtifactHostDocumentForThemeChange(source: source)) {
        // The retained document still carries the old theme CSS.
        _reloadHostDocumentForThemeChange(source!);
        return;
      }
    }
    final controller = _controller;
    if (controller == null) {
      if (source != null && source.trim().isNotEmpty) {
        setState(() {
          _controller = _createController();
        });
      }
    } else {
      if (wasControllerOnly) {
        _scheduleLeaseReattachProbe(controller);
      }
      if (!widget.isRuntimePreview &&
          source != null &&
          source.trim().isNotEmpty &&
          _lastRenderedSource != source &&
          _pendingFinalController == null) {
        // A final source arrived while the webview was unmounted.
        _loadFinalSource(source);
      }
    }
    if (_pendingSource != null) {
      _ensureStreamingUpdateLoop();
    }
  }

  /// Released tier: drop the controller and every piece of bookkeeping that
  /// would make a later regrant skip work (`_lastRenderedSource` in
  /// particular — keeping it would skip the source as "unchanged" → blank).
  /// `_previewHeight` survives so the placeholder keeps the row's extent.
  void _releaseControllerResources() {
    if (_controller == null && _pendingFinalController == null) {
      return;
    }
    _streamingUpdateTimer?.cancel();
    _streamingUpdateTimer = null;
    _takeoverFallbackTimer?.cancel();
    _takeoverFallbackTimer = null;
    _releaseTakeoverPin();
    _controllerGeneration += 1;
    _abandonControllerReadyWaiters();
    _isControllerReady = false;
    _controllerReadyCompleter = null;
    _lastRenderedSource = null;
    _pendingFinalController = null;
    _pendingFinalSource = null;
    _controller = null;
    _runtimeApplyRetryCount = 0;
    _hasRebuiltControllerForApplyFailure = false;
    _isWaitingForHeightRenderCatchUp = false;
    _recordSurfaceLifecycle('lease_released_cleanup');
  }

  /// iOS may terminate the content process of a WKWebView that sat detached;
  /// verify the document still responds after re-attach, reload otherwise.
  void _scheduleLeaseReattachProbe(WebViewController controller) {
    Future<void>.delayed(artifactLeaseReattachProbeDelay, () async {
      if (!mounted ||
          !identical(controller, _controller) ||
          !_leaseAllowsWebView) {
        return;
      }
      var healthy = false;
      String probeResult;
      try {
        final result = await controller
            .runJavaScriptReturningResult(
              "(document.readyState || 'unknown') + ':' + (!!window.__artifactHeight__)",
            )
            .timeout(artifactLeaseReattachProbeTimeout);
        probeResult = result.toString();
        healthy = probeResult.contains(':true');
      } catch (error) {
        probeResult = 'error:$error';
      }
      _recordSurfaceLifecycle(
        'lease_reattach_probe',
        data: <String, dynamic>{
          'result': probeResult,
          'healthy': healthy,
        },
      );
      if (healthy ||
          !mounted ||
          !identical(controller, _controller) ||
          !_leaseAllowsWebView) {
        return;
      }
      _recordSurfaceLifecycle('lease_reattach_reload');
      final source = widget.source;
      _lastRenderedSource = null;
      if (source == null || source.trim().isEmpty) {
        return;
      }
      setState(() {
        _controller = _createController();
      });
    });
  }

  void _releaseStreamingPin() {
    if (_holdsStreamingPin) {
      _holdsStreamingPin = false;
      _leaseHandle?.releasePin();
    }
  }

  void _releaseTakeoverPin() {
    if (_holdsTakeoverPin) {
      _holdsTakeoverPin = false;
      _leaseHandle?.releasePin();
    }
  }

  void _handleWebResourceError(WebResourceError error) {
    if (!mounted) {
      return;
    }
    if (!shouldSurfaceArtifactWebResourceError(
      isForMainFrame: error.isForMainFrame,
    )) {
      _recordSurfaceLifecycle(
        'subresource_error',
        data: <String, dynamic>{
          'errorCode': error.errorCode,
          'errorType': error.errorType?.toString(),
          'description': error.description,
          'url': error.url,
        },
      );
      return;
    }
    setState(() {
      _errorText = error.description;
    });
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
        _sessionRecorder.recordHeightSampled(
          sessionId: _sessionId,
          rawHeight: value,
          clampedHeight: clampedHeight,
          timestamp: DateTime.now(),
          context: sampleContext,
        );
        _heightDebounceTimer?.cancel();
        final nextHeight = resolveNextArtifactPreviewHeight(
          currentAppliedHeight: _previewHeight,
          sampledHeight: clampedHeight,
          isRuntimePreview: widget.isRuntimePreview,
        );
        if (shouldApplyArtifactHeightImmediately(
          currentAppliedHeight: _previewHeight,
          nextResolvedHeight: nextHeight,
          isRuntimePreview: widget.isRuntimePreview,
        )) {
          _applyResolvedArtifactHeight(nextHeight);
          return;
        }
        _heightDebounceTimer = Timer(_heightUpdateDebounceDelay, () {
          if (!mounted) return;
          final nextSampledHeight = _pendingHeight ?? _previewHeight;
          final resolvedHeight = resolveNextArtifactPreviewHeight(
            currentAppliedHeight: _previewHeight,
            sampledHeight: nextSampledHeight,
            isRuntimePreview: widget.isRuntimePreview,
          );
          _applyResolvedArtifactHeight(resolvedHeight);
        });
      },
    );
  }

  void _applyResolvedArtifactHeight(double nextHeight) {
    if (!mounted) {
      return;
    }
    final shouldStartRenderShield = shouldStartArtifactHeightRenderShield(
      currentAppliedHeight: _previewHeight,
      nextResolvedHeight: nextHeight,
      isRuntimePreview: widget.isRuntimePreview,
      enableInternalScroll: widget.enableInternalScroll,
    );
    setState(() {
      _previewHeight = nextHeight;
      if (shouldStartRenderShield) {
        _isWaitingForHeightRenderCatchUp = true;
      }
    });
    _persistPreviewStateToPageStorage(
      previewHeight: nextHeight,
      isPreviewTruncated: false,
    );
    _sessionRecorder.recordHeightApplied(
      sessionId: _sessionId,
      appliedHeight: nextHeight,
      isPreviewTruncated: false,
      timestamp: DateTime.now(),
    );
    if (shouldStartRenderShield) {
      _recordSurfaceLifecycle(
        'height_render_shield_started',
        data: <String, dynamic>{'configuredHeight': nextHeight},
      );
    }
    Logger.temp(
      _artifactPreviewLogTag,
      'artifact height applied',
      reason: 'diagnose inline artifact height sync',
      data: {
        'sourcePath': widget.sourcePath,
        'appliedHeight': nextHeight,
        'isPreviewTruncated': false,
        'startedRenderShield': shouldStartRenderShield,
      },
    );
    _scheduleHeightRenderProbe(configuredHeight: nextHeight);
  }

  void _scheduleHeightRenderProbe({
    required double configuredHeight,
    int frameIndex = 1,
    int? generation,
  }) {
    final probeGeneration = generation ?? ++_heightRenderProbeGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || probeGeneration != _heightRenderProbeGeneration) {
        return;
      }
      final sample = _resolveHostViewportProbeSample();
      final renderHeight = sample.renderHeight;
      final renderGapPx = renderHeight == null
          ? null
          : configuredHeight - renderHeight;
      _recordSurfaceLifecycle(
        'height_apply_render_probe',
        data: <String, dynamic>{
          'probeGeneration': probeGeneration,
          'frameIndex': frameIndex,
          'configuredHeight': configuredHeight,
          'renderHeight': renderHeight,
          'renderGapPx': renderGapPx,
          'probeStatus': sample.status.wireName,
        },
      );
      final remainingFrames = _artifactHeightRenderProbeMaxFrames - frameIndex;
      final shouldContinue = shouldContinueArtifactHeightRenderProbe(
        configuredHeight: configuredHeight,
        renderHeight: renderHeight,
        remainingFrames: remainingFrames,
      );
      if (!shouldContinue &&
          _isWaitingForHeightRenderCatchUp &&
          probeGeneration == _heightRenderProbeGeneration) {
        _recordSurfaceLifecycle(
          'height_render_shield_ended',
          data: <String, dynamic>{
            'probeGeneration': probeGeneration,
            'frameIndex': frameIndex,
            'configuredHeight': configuredHeight,
            'renderHeight': renderHeight,
          },
        );
        setState(() {
          _isWaitingForHeightRenderCatchUp = false;
        });
      }
      if (!shouldContinue) {
        return;
      }
      WidgetsBinding.instance.scheduleFrame();
      _scheduleHeightRenderProbe(
        configuredHeight: configuredHeight,
        frameIndex: frameIndex + 1,
        generation: probeGeneration,
      );
    });
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
    // The timeout keeps `_drainPendingSource`'s in-flight flag from getting
    // stuck forever when onPageFinished never arrives; callers re-check the
    // controller generation after this await.
    await completer.future.timeout(
      artifactControllerReadyTimeout,
      onTimeout: () {},
    );
  }

  /// Releases anything awaiting the current ready completer. Callers that
  /// resume will see a bumped generation and abandon their work.
  void _abandonControllerReadyWaiters() {
    final completer = _controllerReadyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _beginControllerDocumentLoad() {
    _controllerGeneration += 1;
    _abandonControllerReadyWaiters();
    _isControllerReady = false;
    _controllerReadyCompleter = Completer<void>();
  }

  void _markControllerReady() {
    _isControllerReady = true;
    final completer = _controllerReadyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
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
    assert(
      _controller == null ||
          !identical(_controller, _pendingFinalController),
      'The same WebViewController must never be mounted twice.',
    );
    if (!_leaseAllowsWebView) {
      // Lease revoked: same height and chrome as the live preview so the
      // timeline layout does not shift while the webview is unmounted.
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildPreviewShell(
          context,
          isRunning: false,
          shellKey: artifactPreviewLeasePlaceholderKey,
        ),
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
    final showResizeShield =
        _isWaitingForHeightRenderCatchUp && !showWaitingShell;
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
            else if (showResizeShield)
              Positioned.fill(
                child: _buildPreviewShell(
                  context,
                  isRunning: true,
                  shellKey: const Key(_artifactPreviewResizeShieldKey),
                ),
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
                    if (showResizeShield)
                      Positioned.fill(
                        child: _buildPreviewShell(
                          context,
                          isRunning: true,
                          shellKey: const Key(_artifactPreviewResizeShieldKey),
                        ),
                      ),
                  ],
                ),
              ),
              if (!showWaitingShell && !showResizeShield && isUpdating)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _buildSweepOverlay(context),
                  ),
                ),
            ],
          ),
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
    if (_previewHeight == resolved.previewHeight) {
      return;
    }
    _previewHeight = resolved.previewHeight;
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

  Widget _buildPreviewShell(
    BuildContext context, {
    required bool isRunning,
    Key? shellKey,
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
      key: shellKey ?? const Key(_artifactPreviewSweepShellKey),
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
      'sampleDeltaFromPreviousAppliedPx': sampledHeight - previousAppliedHeight,
      'sampledFromPendingFinalController': identical(
        controller,
        pendingFinalController,
      ),
      'hasPendingFinalController': pendingFinalController != null,
      'hostViewportProbeStatus': hostViewportProbe.status.wireName,
      'hostViewportConfiguredHeight':
          hostViewportMetrics?.configuredPreviewHeight,
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
