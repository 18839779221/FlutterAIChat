import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Handles the complete runtime behavior for the `web_search` tool.
class WebSearchToolHandler implements ToolHandler {
  WebSearchToolHandler({
    required WebSearcher webSearcher,
    String Function()? currentMonthYearProvider,
  })  : _webSearcher = webSearcher,
        _currentMonthYearProvider =
            currentMonthYearProvider ?? _defaultCurrentMonthYearProvider;

  final WebSearcher _webSearcher;
  final String Function() _currentMonthYearProvider;

  @override
  ToolDefinition get definition => ToolDefinition(
        name: 'web_search',
        title: 'Web Search',
        localizedTitle:
            const LocalizedToolText(english: 'Web Search', chinese: '联网搜索'),
        descriptionForModel: _buildEnglishDescription(),
        localizedDescriptionForModel: LocalizedToolText(
          english: _buildEnglishDescription(),
          chinese: _buildChineseDescription(),
        ),
        isConcurrencySafe: true,
        parameters: const {
          'query': 'string',
          'maxResults': 'int?',
        },
        argumentSchema: const ToolArgumentSchema(
          properties: {
            'query': ToolArgumentProperty.string(
              description:
                  'Short and specific web search query focused on the entity, topic, and qualifiers.',
              localizedDescription: LocalizedToolText(
                english:
                    'Short and specific web search query focused on the entity, topic, and qualifiers.',
                chinese: '短而具体的联网搜索词，应尽量聚焦实体、主题和限定词。',
              ),
            ),
            'maxResults': ToolArgumentProperty.integer(
              description:
                  'Maximum number of search results to return; usually 3 to 5 is enough.',
              localizedDescription: LocalizedToolText(
                english:
                    'Maximum number of search results to return; usually 3 to 5 is enough.',
                chinese: '最多返回多少条搜索结果，通常 3 到 5 条即可。',
              ),
            ),
          },
          required: ['query'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final query = rawArguments['query'];
    if (query is! String || query.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_query',
        errorSummary: '联网搜索失败：缺少有效查询词',
      );
    }

    final maxResults =
        rawArguments['maxResults'] ?? rawArguments['num_results'];
    final normalizedMaxResults =
        maxResults is num ? maxResults.toInt().clamp(1, 10) : 5;
    return ToolArgumentResolution.valid({
      'query': query.trim(),
      'maxResults': normalizedMaxResults,
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _webSearcher(
      query: context.arguments['query'] as String,
      maxResults: context.arguments['maxResults'] as int?,
    );
  }
  String _buildEnglishDescription() {
    final currentMonthYear = _currentMonthYearProvider();
    return '''
Allows the model to search the web and use the results to inform responses.
Provides up-to-date information for current events, recent changes, and external references beyond the model's knowledge cutoff.
Returns search result information including titles, snippets, and URLs that can be cited in the final answer.
If the user already provided a URL, prefer fetch_webpage. If the question only depends on current chat context, prefer search_chat_history.

CRITICAL REQUIREMENT - You MUST follow this:
- After answering the user's question, you MUST include a "Sources:" section at the end of your response.
- In the Sources section, list all relevant URLs from the search results as markdown hyperlinks: [Title](URL).
- This is mandatory.

IMPORTANT - Use the correct year in search queries:
- The current month is $currentMonthYear. You MUST use this year when searching for recent information, documentation, or current events.
- If the user asks for "latest" information, do not default to last year.
''';
  }

  String _buildChineseDescription() {
    final currentMonthYear = _currentMonthYearProvider();
    return '''
当用户需要联网获取最新信息、当前事件、近期变化、外部参考资料或超出模型知识截止时间的信息时使用。
搜索结果会返回标题、摘要与 URL，供最终答复引用。
如果用户已经提供 URL，应优先使用 fetch_webpage；如果问题只依赖当前聊天上下文，应优先使用 search_chat_history。

关键要求：
- 在基于联网搜索作答后，最终答复末尾必须包含 "Sources:" 小节。
- 在 Sources 小节中，必须把相关链接写成 Markdown 超链接：[标题](URL)。

重要要求 - 搜索查询必须使用正确的当前年份：
- 当前月份是 $currentMonthYear。在搜索最新信息、最新文档、最近变化或当前事件时，必须使用当前年份。
- 当用户要求“最新”内容时，不要默认使用去年的年份。
''';
  }

  static String _defaultCurrentMonthYearProvider() {
    final now = DateTime.now();
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[now.month - 1]} ${now.year}';
  }
}
