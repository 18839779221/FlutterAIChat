import 'package:ai_chat/models/artifact/artifact_turn_projection.dart';
import 'package:ai_chat/pages/artifact_detail_page.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/material.dart';

final Map<String, GlobalKey> _artifactPreviewSurfaceKeys =
    <String, GlobalKey>{};

GlobalKey _artifactPreviewSurfaceKeyFor(String cacheKey) {
  return _artifactPreviewSurfaceKeys.putIfAbsent(
    cacheKey,
    () => GlobalKey(debugLabel: 'artifact-preview:$cacheKey'),
  );
}

/// Lightweight inline artifact card.
class ArtifactBlock extends StatelessWidget {
  const ArtifactBlock({
    super.key,
    required this.projection,
    this.logicalId,
  });

  final ArtifactTurnProjection? projection;
  final String? logicalId;

  @override
  Widget build(BuildContext context) {
    final artifact = projection;
    Logger.temp(
      'ArtifactBlock',
      'build called',
      reason: 'diagnose streaming performance',
      data: {
        'hasArtifact': artifact != null,
        'artifactId': artifact?.artifactId ?? 'null',
        'logicalId': logicalId ?? 'null',
        'previewCacheKey': artifact == null
            ? 'null'
            : _buildArtifactPreviewCacheKey(artifact),
        'sourceLength': artifact?.source?.length ?? 0,
        'sourcePath': artifact?.sourcePath ?? 'null',
      },
    );
    if (artifact == null) {
      return const SizedBox.shrink();
    }
    final previewCacheKey = _buildArtifactPreviewCacheKey(artifact);

    return GestureDetector(
      key: ValueKey('inner_gesture_$previewCacheKey'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ArtifactDetailPage(projection: artifact),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ArtifactPreviewSurface(
          key: _artifactPreviewSurfaceKeyFor(previewCacheKey),
          artifactId: artifact.artifactId,
          source: artifact.source,
          sourcePath: artifact.sourcePath,
          isRuntimePreview: artifact.isRuntimePreview,
          turnId: artifact.turnId,
          providerCallId: artifact.providerCallId,
        ),
      ),
    );
  }

  String _buildArtifactPreviewCacheKey(ArtifactTurnProjection artifact) {
    final trimmedLogicalId = logicalId?.trim();
    if (trimmedLogicalId != null && trimmedLogicalId.isNotEmpty) {
      return trimmedLogicalId;
    }
    final providerCallId = artifact.providerCallId?.trim();
    if (providerCallId != null && providerCallId.isNotEmpty) {
      return 'artifact:$providerCallId';
    }
    return 'artifact:${artifact.turnId}:${artifact.artifactId}';
  }
}
