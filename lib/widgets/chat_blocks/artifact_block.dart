import 'package:ai_chat/models/artifact/artifact_turn_projection.dart';
import 'package:ai_chat/pages/artifact_detail_page.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:ai_chat/widgets/chat_timeline/stable_artifact_block.dart';
import 'package:flutter/material.dart';

/// Lightweight inline artifact card.
class ArtifactBlock extends StatelessWidget {
  const ArtifactBlock({
    super.key,
    required this.projection,
  });

  final ArtifactTurnProjection? projection;

  @override
  Widget build(BuildContext context) {
    final artifact = projection;
    if (artifact == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
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
        child: StableArtifactBlock(
          cacheKey: _buildArtifactCacheKey(artifact),
          builder: (_) => ArtifactPreviewSurface(
            source: artifact.source,
            isStale: artifact.isStale,
            sourcePath: artifact.sourcePath,
          ),
        ),
      ),
    );
  }

  String _buildArtifactCacheKey(ArtifactTurnProjection artifact) {
    return [
      artifact.artifactId,
      artifact.sourcePath,
      artifact.isStale ? 'stale' : 'fresh',
      artifact.updatedAt.microsecondsSinceEpoch.toString(),
      artifact.source?.hashCode.toString() ?? 'no-source',
    ].join(':');
  }
}
