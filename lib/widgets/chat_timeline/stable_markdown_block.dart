import 'package:flutter/material.dart';

/// Keeps completed markdown content mounted longer so scrolling feels steadier.
class StableMarkdownBlock extends StatefulWidget {
  /// Stable identity for unchanged markdown content.
  final String cacheKey;

  /// The markdown renderer subtree.
  final Widget child;

  const StableMarkdownBlock({
    super.key,
    required this.cacheKey,
    required this.child,
  });

  @override
  State<StableMarkdownBlock> createState() => _StableMarkdownBlockState();
}

class _StableMarkdownBlockState extends State<StableMarkdownBlock>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return KeyedSubtree(
      key: ValueKey(widget.cacheKey),
      child: widget.child,
    );
  }
}
