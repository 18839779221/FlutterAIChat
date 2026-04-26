import '../models/llm/base_llm.dart';
import '../models/tool/tool_invocation.dart';
import 'prompt/prompt_locale.dart';
import 'tool_call_service.dart';
import '../utils/logger.dart';

class ChatConfig {
  String systemPrompt = "";
  String userSystemPrompt = "";
  PromptLocale promptLocale = PromptLocale.english;

  ChatConfig({
    required this.systemPrompt,
    this.userSystemPrompt = '',
    this.promptLocale = PromptLocale.english,
  });
}

class ChatService {
  static const String _tag = 'ChatService';
  final BaseLLM _llm;
  final ToolCallService? _toolCallService;

  ChatService({
    required BaseLLM llm,
    ToolCallService? toolCallService,
  })  : _llm = llm,
        _toolCallService = toolCallService;

  // 暴露LLM实例供外部使用
  BaseLLM get llm => _llm;

  /// Returns the runtime model name that budget services should evaluate.
  String getModelName(ChatConfig config) {
    return _llm.getModelName(config);
  }

  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
    ToolExecutionStartedCallback? onExecutionStarted,
  }) async {
    final toolCallService = _toolCallService;
    if (toolCallService == null) {
      return const ToolPreparationResult.noTool();
    }

    try {
      return await toolCallService.executeToolInvocation(
        groupId: groupId,
        invocation: invocation,
        trustTool: trustTool,
        turnId: turnId,
        onExecutionStarted: onExecutionStarted,
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '工具执行失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      return const ToolPreparationResult.noTool();
    }
  }
}
