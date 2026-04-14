import '../models/tool/tool_access_snapshot.dart';
/// Selects the subset of tools that should be visible to the planner for the
/// current user turn.
class PlannerToolExposureService {
  /// Main planner exposure entry: the planner consumes access snapshots rather
  /// than re-deriving blocked/confirmation semantics from ad-hoc inputs.
  List<ToolAccessSnapshot> selectVisibleToolAccess({
    required String userInput,
    required List<ToolAccessSnapshot> allTools,
  }) {
    if (allTools.isEmpty) {
      return const [];
    }

    final seen = <String>{};
    return allTools
        .where((tool) => tool.isVisibleToPlanner)
        .where((tool) => seen.add(tool.definition.name))
        .toList(growable: false);
  }
}
