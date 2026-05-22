import '../../models/chat_message.dart';
import '../../models/skill/duplicate_skill_invocation_mode.dart';
import '../../models/skill/skill_descriptor.dart';
import '../../models/skill/invoked_skill_context.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/tool_result.dart';
import '../../repositories/app_settings_repository.dart';
import '../../services/skills/skill_invocation_guard.dart';
import '../../services/skills/skill_context_formatter.dart';
import '../../services/skills/skill_runtime_service.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Explicitly loads one available skill into the current conversation flow.
class SkillToolHandler extends ToolHandler {
  SkillToolHandler({
    required SkillRuntimeService skillRuntimeService,
    AppSettingsRepository? settingsRepository,
    SkillInvocationGuard invocationGuard = const SkillInvocationGuard(),
    SkillContextFormatter skillContextFormatter = const SkillContextFormatter(),
  })  : _skillRuntimeService = skillRuntimeService,
        _settingsRepository = settingsRepository,
        _invocationGuard = invocationGuard,
        _skillContextFormatter = skillContextFormatter;

  final SkillRuntimeService _skillRuntimeService;
  final AppSettingsRepository? _settingsRepository;
  final SkillInvocationGuard _invocationGuard;
  final SkillContextFormatter _skillContextFormatter;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'skill',
        title: 'Skill',
        localizedTitle: LocalizedToolText(
          english: 'Skill',
          chinese: '技能',
        ),
        descriptionForModel:
            'When the current task clearly matches one of the available skills listed in system-reminder messages, you must invoke this tool before continuing. Use it to load the selected skill instructions into the main conversation. Do not mention a skill without actually calling this tool.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'When the current task clearly matches one of the available skills listed in system-reminder messages, you must invoke this tool before continuing. Use it to load the selected skill instructions into the main conversation. Do not mention a skill without actually calling this tool.',
          chinese:
              '当当前任务明显匹配 system-reminder 中列出的某个可用技能时，必须先调用此工具，再继续后续响应。使用它把所选技能的指令加载进主对话。不要只提到技能却不真正调用此工具。',
        ),
        argumentSchema: ToolArgumentSchema(
          properties: {
            'skill': ToolArgumentProperty.string(
              description:
                  'Skill name or canonical skill identifier to invoke.',
              localizedDescription: LocalizedToolText(
                english: 'Skill name or canonical skill identifier to invoke.',
                chinese: '要调用的技能名称或规范技能标识。',
              ),
            ),
            'args': ToolArgumentProperty.string(
              description:
                  'Optional raw argument string reserved for future skill-specific use.',
              localizedDescription: LocalizedToolText(
                english:
                    'Optional raw argument string reserved for future skill-specific use.',
                chinese: '可选原始参数字符串，预留给未来技能特定用法。',
              ),
            ),
          },
          required: ['skill'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final skill = rawArguments['skill'];
    if (skill is! String || skill.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_skill',
        errorSummary: 'Skill failed: missing skill name',
      );
    }

    final args = rawArguments['args'];
    return ToolArgumentResolution.valid({
      'skill': skill.trim(),
      if (args is String && args.trim().isNotEmpty) 'args': args.trim(),
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final skillName = (context.arguments['skill'] as String?)?.trim() ?? '';
    final descriptor = await _skillRuntimeService.loadSkillById(skillName);
    if (descriptor == null || !descriptor.isEnabled) {
      return ToolResult(
        toolName: 'skill',
        status: ToolExecutionStatus.failure,
        summary: 'Skill failed: skill not available',
        data: {
          'skill': skillName,
        },
        errorMessage: 'skill_not_available',
      );
    }
    if (_invocationGuard.wasSkillInvoked(
      events: context.currentTurnEvents,
      skillId: descriptor.id,
      skillName: descriptor.name,
    )) {
      final mode =
          await _settingsRepository?.getDuplicateSkillInvocationMode() ??
              DuplicateSkillInvocationMode.reuse;
      if (mode == DuplicateSkillInvocationMode.reuse) {
        return ToolResult(
          toolName: 'skill',
          status: ToolExecutionStatus.success,
          summary: 'Skill reused: ${descriptor.name}',
          data: {
            'skillId': descriptor.id,
            'name': descriptor.name,
            'duplicateInvocation': true,
            'reloadPerformed': false,
          },
        );
      }

      final reloaded = _buildInvokedContext(descriptor);
      return ToolResult(
        toolName: 'skill',
        status: ToolExecutionStatus.success,
        summary: 'Skill reloaded: ${descriptor.name}',
        data: {
          ...reloaded.toJson(),
          'duplicateInvocation': true,
          'reloadPerformed': true,
        },
      );
    }

    final invoked = _buildInvokedContext(descriptor);

    return ToolResult(
      toolName: 'skill',
      status: ToolExecutionStatus.success,
      summary: 'Skill loaded: ${descriptor.name}',
      data: {
        ...invoked.toJson(),
        'duplicateInvocation': false,
        'reloadPerformed': true,
      },
    );
  }

  InvokedSkillContext _buildInvokedContext(SkillDescriptor descriptor) {
    return _skillContextFormatter.prepareInvokedContext(
      InvokedSkillContext(
        skillId: descriptor.id,
        name: descriptor.name,
        qualifiedPath: descriptor.skillRootPath,
        baseDirectory: descriptor.skillRootPath,
        instructionBody: descriptor.bodyText,
      ),
    );
  }
}
