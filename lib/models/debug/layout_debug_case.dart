import 'package:ai_chat/models/debug/layout_debug_block.dart';

/// One fixed layout regression case shown on the document debug page.
class LayoutDebugCase {
  /// Stable identifier used for selection state and test targeting.
  final String id;

  /// Human-readable case title shown in the page navigation.
  final String title;

  /// Short explanation of which layout risks the case is meant to cover.
  final String description;

  /// Ordered preview blocks rendered for this case.
  final List<LayoutDebugBlock> blocks;

  const LayoutDebugCase({
    required this.id,
    required this.title,
    required this.description,
    required this.blocks,
  });
}
