import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_definition.dart';
import '../models/tool/tool_policy.dart';
import '../repositories/app_settings_repository.dart';
import 'image_generation_config_resolver.dart';
import '../utils/logger.dart';

class ToolPolicyService {
  static const _tag = 'ToolPolicyService';

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

  Future<ToolAccessSnapshot> resolveToolAccess(ToolDefinition tool) async {
    if (tool.name == 'generate_image' &&
        !await _hasImageGenerationRuntimeConfig()) {
      Logger.i(
        _tag,
        'resolveToolAccess tool=${tool.name} decision=blocked source=image_generation_not_configured',
      );
      return _buildToolAccess(
        tool,
        ToolPolicyDecision.blocked,
      );
    }

    final blockedTools = await _repository.getBlockedToolNames();
    if (blockedTools.contains(tool.name)) {
      Logger.i(
        _tag,
        'resolveToolAccess tool=${tool.name} decision=blocked source=blocked_list',
      );
      return _buildToolAccess(
        tool,
        ToolPolicyDecision.blocked,
      );
    }

    final trustedTools = await _repository.getTrustedToolNames();
    if (trustedTools.contains(tool.name)) {
      Logger.i(
        _tag,
        'resolveToolAccess tool=${tool.name} decision=autoRun source=trusted_list',
      );
      return _buildToolAccess(
        tool,
        ToolPolicyDecision.autoRun,
      );
    }

    final mode = await getExecutionMode();
    final executionDecision = switch (mode) {
      ToolExecutionMode.conservative => tool.requiresConfirmation
          ? ToolPolicyDecision.requireConfirmation
          : ToolPolicyDecision.autoRun,
      ToolExecutionMode.balanced => tool.requiresConfirmation
          ? ToolPolicyDecision.requireConfirmation
          : ToolPolicyDecision.autoRun,
      ToolExecutionMode.aggressive => ToolPolicyDecision.autoRun,
    };
    return _buildToolAccess(tool, executionDecision);
  }

  Future<ToolPolicyDecision> resolveExecutionMode(ToolDefinition tool) async {
    return (await resolveToolAccess(tool)).executionDecision;
  }

  Future<void> trustTool(String toolName) {
    return _repository.addTrustedToolName(toolName);
  }

  Future<void> untrustTool(String toolName) {
    return _repository.removeTrustedToolName(toolName);
  }

  Future<Set<String>> getBlockedToolNames() {
    return _repository.getBlockedToolNames();
  }

  Future<void> blockTool(String toolName) {
    return _repository.addBlockedToolName(toolName);
  }

  Future<void> unblockTool(String toolName) {
    return _repository.removeBlockedToolName(toolName);
  }

  ToolAccessSnapshot _buildToolAccess(
    ToolDefinition tool,
    ToolPolicyDecision executionDecision,
  ) {
    return ToolAccessSnapshot.fromDecision(
      definition: tool,
      executionDecision: executionDecision,
    );
  }

  Future<bool> _hasImageGenerationRuntimeConfig() async {
    final providers = await _repository.getProviders();
    final additionalConfig = await _repository.getAdditionalConfig();
    return const ImageGenerationConfigResolver().resolve(
          providers: providers,
          additionalConfig: additionalConfig,
        ) !=
        null;
  }
}
