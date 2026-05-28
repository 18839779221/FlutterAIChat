import 'package:ai_chat/utils/logger.dart';
import 'package:flutter/material.dart';

/// Keeps an artifact subtree stable across unrelated parent rebuilds.
class StableArtifactBlock extends StatefulWidget {
  /// Stable identity for the rendered artifact content.
  final String cacheKey;

  /// Builds the artifact subtree when the cache key changes.
  final WidgetBuilder builder;

  const StableArtifactBlock({
    super.key,
    required this.cacheKey,
    required this.builder,
  });

  @override
  State<StableArtifactBlock> createState() => _StableArtifactBlockState();
}

class _StableArtifactBlockState extends State<StableArtifactBlock>
    with AutomaticKeepAliveClientMixin {
  String? _cachedKey;
  Widget? _cachedChild;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final willRebuild = _cachedKey != widget.cacheKey || _cachedChild == null;
    Logger.temp(
      'StableArtifactBlock',
      'build called',
      reason: 'diagnose streaming performance',
      data: {
        'cacheKey': widget.cacheKey,
        'cachedKey': _cachedKey,
        'willRebuild': willRebuild,
      },
    );
    if (willRebuild) {
      _cachedKey = widget.cacheKey;
      _cachedChild = widget.builder(context);
    }

    return KeyedSubtree(
      key: ValueKey(widget.cacheKey),
      child: _cachedChild!,
    );
  }
}
