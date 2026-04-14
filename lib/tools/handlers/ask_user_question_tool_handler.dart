import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Planner-visible interaction tool used to collect missing user input before
/// continuing the current turn.
class AskUserQuestionToolHandler implements ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'ask_user_question',
        title: '向用户提问',
        description: '当完成当前任务缺少关键信息时，向用户发起结构化问题卡片。',
        descriptionForModel:
            '当你无法继续当前任务、且缺少的关键信息只能由用户补充时，必须优先调用此工具，而不是直接用普通文本提问。适合单题、多题、单选、多选和 Other 自定义输入。用户回答后，系统会在同一个 turn 内继续执行。',
        whenToUse: [
          '完成任务所需的关键信息尚未提供，且不能安全假设',
          '你想一次性收集多个决定后续方案的问题',
          '你希望用户从结构化选项中选择，而不是自由文本来回澄清',
        ],
        whenNotToUse: [
          '现有信息已经足够，可以直接回答',
          '缺的不是用户偏好，而是应该通过其他工具获取的客观信息',
          '只是想补充说明、寒暄或做非关键追问',
        ],
        runtimeKind: ToolRuntimeKind.userInteraction,
        argumentSchema: ToolArgumentSchema(
          properties: {
            'questions': ToolArgumentProperty(
              type: 'array',
              description:
                  '问题列表。每项应包含 id、header、question、multiSelect、options；options 为 label/description 列表。',
            ),
          },
          required: ['questions'],
        ),
        argumentExamples: {
          'questions': [
            {
              'id': 'storage_layer',
              'header': '存储',
              'question': '你希望使用哪种本地存储方案？',
              'multiSelect': false,
              'options': [
                {
                  'label': 'SQLite',
                  'description': '关系型，本地查询稳定',
                },
                {
                  'label': 'Isar (Recommended)',
                  'description': '对象存储，适合 Flutter 本地数据',
                },
              ],
            },
          ],
        },
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final questions = rawArguments['questions'];
    if (questions is! List || questions.isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_questions',
        errorSummary: '向用户提问失败：至少需要一个问题',
      );
    }
    return ToolArgumentResolution.valid({
      'questions': questions,
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    return const ToolResult(
      toolName: 'ask_user_question',
      status: ToolExecutionStatus.failure,
      summary: 'ask_user_question 不应走立即执行链路',
      data: {
        'reason': 'interactive_tool_should_suspend_turn',
      },
      errorMessage: 'interactive_tool_should_suspend_turn',
    );
  }

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return const [];
  }
}
