import '../models/tool/tool_definition.dart';
import '../models/tool/tool_policy.dart';
import '../repositories/app_settings_repository.dart';

class ToolPolicyService {
  ToolPolicyService({
    required AppSettingsRepository repository,
  }) : _repository = repository;

  final AppSettingsRepository _repository;

  Future<ToolExecutionMode> getExecutionMode() async {
    final storedName = await _repository.getToolExecutionModeName();
    if (storedName == null) {
      return ToolExecutionMode.balanced;
    }

    final matched = ToolExecutionMode.values.where(
      (value) => value.name == storedName,
    );
    if (matched.isEmpty) {
      return ToolExecutionMode.balanced;
    }

    return matched.first;
  }

  Future<void> saveExecutionMode(ToolExecutionMode mode) {
    return _repository.saveToolExecutionModeName(mode.name);
  }

  Future<ToolPolicyDecision> resolveExecutionMode(ToolDefinition tool) async {
    final trustedTools = await _repository.getTrustedToolNames();
    if (trustedTools.contains(tool.name)) {
      return ToolPolicyDecision.autoRun;
    }

    final mode = await getExecutionMode();
    switch (mode) {
      case ToolExecutionMode.conservative:
        return tool.requiresConfirmation
            ? ToolPolicyDecision.requireConfirmation
            : ToolPolicyDecision.autoRun;
      case ToolExecutionMode.balanced:
        return tool.requiresConfirmation
            ? ToolPolicyDecision.requireConfirmation
            : ToolPolicyDecision.autoRun;
      case ToolExecutionMode.aggressive:
        return ToolPolicyDecision.autoRun;
    }
  }

  Future<void> trustTool(String toolName) {
    return _repository.addTrustedToolName(toolName);
  }

  Future<void> untrustTool(String toolName) {
    return _repository.removeTrustedToolName(toolName);
  }
}
