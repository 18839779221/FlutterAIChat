import 'package:ai_chat/models/artifact/artifact_turn_projection.dart';
import 'package:ai_chat/pages/artifact_detail_page.dart';
import 'package:ai_chat/utils/logger.dart';
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
    Logger.temp(
      'ArtifactBlock',
      'build called',
      reason: 'diagnose streaming performance',
      data: {
        'hasArtifact': artifact != null,
        'artifactId': artifact?.artifactId ?? 'null',
        'sourceLength': artifact?.source?.length ?? 0,
        'sourcePath': artifact?.sourcePath ?? 'null',
      },
    );
    if (artifact == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      key: ValueKey('inner_gesture_${_buildArtifactCacheKey(artifact)}'),
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
          key: ValueKey(_buildArtifactCacheKey(artifact)),
          cacheKey: _buildArtifactCacheKey(artifact),
          builder: (context) => ArtifactPreviewSurface(
            source: artifact.source,
            sourcePath: artifact.sourcePath,
          ),
        ),
      ),
    );
  }

  String _buildArtifactCacheKey(ArtifactTurnProjection artifact) {
    return artifact.artifactId;
  }
}
