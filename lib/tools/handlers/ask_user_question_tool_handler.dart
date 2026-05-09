import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Planner-visible interaction tool used to collect missing user input before
/// continuing the current turn.
class AskUserQuestionToolHandler extends ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'ask_user_question',
        title: 'Ask User Question',
        localizedTitle: LocalizedToolText(
          english: 'Ask User Question',
          chinese: '向用户提问',
        ),
        descriptionForModel:
            'When you cannot continue the current task and the missing critical information can only come from the user, you must prefer this tool instead of asking in plain assistant text. It supports single-question, multi-question, single-select, multi-select, and Other custom input. After the user answers, the system continues within the same turn.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'When you cannot continue the current task and the missing critical information can only come from the user, you must prefer this tool instead of asking in plain assistant text. It supports single-question, multi-question, single-select, multi-select, and Other custom input. After the user answers, the system continues within the same turn.',
          chinese:
              '当你无法继续当前任务、且缺少的关键信息只能由用户补充时，必须优先调用此工具，而不是直接用普通文本提问。适合单题、多题、单选、多选和 Other 自定义输入。用户回答后，系统会在同一个 turn 内继续执行。',
        ),
        runtimeKind: ToolRuntimeKind.userInteraction,
        argumentSchema: ToolArgumentSchema(
          properties: {
            'questions': ToolArgumentProperty(
              type: 'array',
              description:
                  'List of questions. Each item should include id, header, question, multiSelect, and options; options are label/description pairs.',
              localizedDescription: LocalizedToolText(
                english:
                    'List of questions. Each item should include id, header, question, multiSelect, and options; options are label/description pairs.',
                chinese:
                    '问题列表。每项应包含 id、header、question、multiSelect、options；options 为 label/description 列表。',
              ),
              items: ToolArgumentProperty(
                type: 'object',
                description: 'Definition of one structured question.',
                localizedDescription: LocalizedToolText(
                  english: 'Definition of one structured question.',
                  chinese: '单个结构化问题定义。',
                ),
                required: ['id', 'question'],
                additionalProperties: false,
                properties: {
                  'id': ToolArgumentProperty.string(
                    description:
                        'Stable question id used to map the user answer back.',
                    localizedDescription: LocalizedToolText(
                      english:
                          'Stable question id used to map the user answer back.',
                      chinese: '稳定问题 id，用于回填用户答案。',
                    ),
                  ),
                  'header': ToolArgumentProperty.string(
                    description: 'Short heading shown above the question.',
                    localizedDescription: LocalizedToolText(
                      english: 'Short heading shown above the question.',
                      chinese: '显示在问题上方的短标题。',
                    ),
                  ),
                  'question': ToolArgumentProperty.string(
                    description: 'The actual question shown to the user.',
                    localizedDescription: LocalizedToolText(
                      english: 'The actual question shown to the user.',
                      chinese: '真正向用户展示的问题内容。',
                    ),
                  ),
                  'multiSelect': ToolArgumentProperty(
                    type: 'boolean',
                    description:
                        'Whether the user can choose multiple options.',
                    localizedDescription: LocalizedToolText(
                      english:
                          'Whether the user can choose multiple options.',
                      chinese: '是否允许用户多选。',
                    ),
                  ),
                  'options': ToolArgumentProperty(
                    type: 'array',
                    description: 'List of selectable options.',
                    localizedDescription: LocalizedToolText(
                      english: 'List of selectable options.',
                      chinese: '可选项列表。',
                    ),
                    items: ToolArgumentProperty(
                      type: 'object',
                      description: 'Definition of one selectable option.',
                      localizedDescription: LocalizedToolText(
                        english: 'Definition of one selectable option.',
                        chinese: '单个可选项定义。',
                      ),
                      required: ['label'],
                      additionalProperties: false,
                      properties: {
                        'label': ToolArgumentProperty.string(
                          description: 'Option title shown to the user.',
                          localizedDescription: LocalizedToolText(
                            english: 'Option title shown to the user.',
                            chinese: '选项标题。',
                          ),
                        ),
                        'description': ToolArgumentProperty.string(
                          description:
                              'Optional explanatory text for the option.',
                          localizedDescription: LocalizedToolText(
                            english:
                                'Optional explanatory text for the option.',
                            chinese: '选项说明文字。',
                          ),
                        ),
                        'isRecommended': ToolArgumentProperty(
                          type: 'boolean',
                          description: 'Whether this option is recommended.',
                          localizedDescription: LocalizedToolText(
                            english: 'Whether this option is recommended.',
                            chinese: '是否为推荐选项。',
                          ),
                        ),
                      },
                    ),
                  ),
                },
              ),
            ),
          },
          required: ['questions'],
        ),
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

}
