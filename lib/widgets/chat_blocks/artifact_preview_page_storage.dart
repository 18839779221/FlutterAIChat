import 'package:flutter/material.dart';

/// Persisted inline preview UI state keyed by artifact id.
class ArtifactPreviewPageStorageSnapshot {
  /// Last measured preview height after clamping.
  final double previewHeight;

  /// Whether the preview was truncated at the stored height.
  final bool isPreviewTruncated;

  const ArtifactPreviewPageStorageSnapshot({
    required this.previewHeight,
    required this.isPreviewTruncated,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'previewHeight': previewHeight,
      'isPreviewTruncated': isPreviewTruncated,
    };
  }

  static ArtifactPreviewPageStorageSnapshot? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final previewHeight = switch (value['previewHeight']) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };
    final isPreviewTruncated = value['isPreviewTruncated'];
    if (previewHeight == null || isPreviewTruncated is! bool) {
      return null;
    }
    return ArtifactPreviewPageStorageSnapshot(
      previewHeight: previewHeight,
      isPreviewTruncated: isPreviewTruncated,
    );
  }
}

/// Resolved inline preview UI state used during surface initialization.
class ArtifactPreviewVisualState {
  /// Current preview height for the inline surface container.
  final double previewHeight;

  /// Whether the current height implies truncation messaging.
  final bool isPreviewTruncated;

  const ArtifactPreviewVisualState({
    required this.previewHeight,
    required this.isPreviewTruncated,
  });
}

ArtifactPreviewVisualState resolveArtifactPreviewVisualState({
  required ArtifactPreviewPageStorageSnapshot? cachedSnapshot,
  required double defaultPreviewHeight,
}) {
  if (cachedSnapshot == null) {
    return ArtifactPreviewVisualState(
      previewHeight: defaultPreviewHeight,
      isPreviewTruncated: false,
    );
  }
  return ArtifactPreviewVisualState(
    previewHeight: cachedSnapshot.previewHeight,
    isPreviewTruncated: cachedSnapshot.isPreviewTruncated,
  );
}

String artifactPreviewPageStorageKey(String artifactId) {
  return 'artifact_preview_snapshot:$artifactId';
}

ArtifactPreviewPageStorageSnapshot? readArtifactPreviewPageStorageSnapshot({
  required BuildContext context,
  required String artifactId,
}) {
  final storage = PageStorage.maybeOf(context);
  if (storage == null) {
    return null;
  }
  final raw = storage.readState(
    context,
    identifier: artifactPreviewPageStorageKey(artifactId),
  );
  return ArtifactPreviewPageStorageSnapshot.fromJson(raw);
}

void writeArtifactPreviewPageStorageSnapshot({
  required BuildContext context,
  required String artifactId,
  required ArtifactPreviewPageStorageSnapshot snapshot,
}) {
  final storage = PageStorage.maybeOf(context);
  if (storage == null) {
    return;
  }
  storage.writeState(
    context,
    snapshot.toJson(),
    identifier: artifactPreviewPageStorageKey(artifactId),
  );
}
