import '../models/tool/tool_definition.dart';

/// Selects the subset of tools that should be visible to the planner for the
/// current user turn.
class PlannerToolExposureService {
  List<ToolDefinition> selectVisibleTools({
    required String userInput,
    required List<ToolDefinition> allTools,
  }) {
    if (allTools.isEmpty) {
      return const [];
    }

    final seen = <String>{};
    return allTools
        .where((tool) => seen.add(tool.name))
        .toList(growable: false);
  }
}
