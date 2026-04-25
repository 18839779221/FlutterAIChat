import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Handles the complete runtime behavior for the `fetch_webpage` tool.
class FetchWebpageToolHandler implements ToolHandler {
  FetchWebpageToolHandler({
    required WebpageFetcher webpageFetcher,
  }) : _webpageFetcher = webpageFetcher;

  final WebpageFetcher _webpageFetcher;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'fetch_webpage',
        title: 'Fetch Webpage',
        localizedTitle: LocalizedToolText(
          english: 'Fetch Webpage',
          chinese: '读取网页',
        ),
        descriptionForModel:
            'Read a public webpage at a specific URL and process its content according to a prompt.\n\n'
            'IMPORTANT: This tool is for public, unauthenticated webpages. It may fail for private or authenticated URLs such as Google Docs, Confluence, Jira, GitHub pages that require login, or other workspace-only content. Before using this tool, check whether a specialized MCP tool or another authenticated integration is available, and prefer that when possible.\n\n'
            'Use this tool when you already have a concrete URL and need to read or process that page for a specific purpose.\n\n'
            'This tool fetches the webpage, extracts readable content, and uses an internal side model to process that content according to the prompt. It returns the processed result rather than simply returning the raw page text. If the page is very long, the result may be condensed. If the URL redirects to a different host, the tool may require a new request using the redirected URL.\n\n'
            'Do not use this tool just to discover relevant pages; use web_search first when you need to find candidate sources. Do not use this tool for GitHub resources that are better handled by Bash or dedicated tools.\n\n'
            'This tool is read-only and does not modify files.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Read a public webpage at a specific URL and process its content according to a prompt.\n\n'
              'IMPORTANT: This tool is for public, unauthenticated webpages. It may fail for private or authenticated URLs such as Google Docs, Confluence, Jira, GitHub pages that require login, or other workspace-only content. Before using this tool, check whether a specialized MCP tool or another authenticated integration is available, and prefer that when possible.\n\n'
              'Use this tool when you already have a concrete URL and need to read or process that page for a specific purpose.\n\n'
              'This tool fetches the webpage, extracts readable content, and uses an internal side model to process that content according to the prompt. It returns the processed result rather than simply returning the raw page text. If the page is very long, the result may be condensed. If the URL redirects to a different host, the tool may require a new request using the redirected URL.\n\n'
              'Do not use this tool just to discover relevant pages; use web_search first when you need to find candidate sources. Do not use this tool for GitHub resources that are better handled by Bash or dedicated tools.\n\n'
              'This tool is read-only and does not modify files.',
          chinese:
              '读取指定公共网页，并按 prompt 处理网页内容。\n\n'
              '重要：该工具只适用于公开、无需认证的网页。对于 Google Docs、Confluence、Jira、需要登录的 GitHub 页面或其他仅限工作区访问的内容，工具可能失败。调用前应先判断是否有更合适的专用 MCP 工具或其他带认证能力的集成，并在可用时优先使用。\n\n'
              '当你已经有明确 URL，并且需要出于某个具体目的读取或处理该页面时使用此工具。\n\n'
              '该工具会抓取网页、提取可读内容，并使用内部 side model 按 prompt 处理这些内容。返回结果是处理后的网页结果，而不是简单返回原始网页文本。如果页面过长，结果可能会被压缩。如果 URL 跳转到其他 host，工具可能要求使用跳转后的 URL 重新发起请求。\n\n'
              '不要把它用于单纯发现候选网页；如果还需要先找来源，应先使用 web_search。对于更适合由 Bash 或专用工具处理的 GitHub 资源，也不要使用此工具。\n\n'
              '该工具为只读工具，不会修改文件。',
        ),
        parameters: {
          'url': 'string',
          'prompt': 'string',
        },
        argumentSchema: ToolArgumentSchema(
          properties: {
            'url': ToolArgumentProperty.string(
              description: 'Fully qualified public URL to read.',
              localizedDescription: LocalizedToolText(
                english: 'Fully qualified public URL to read.',
                chinese: '要读取的完整公共网页链接。',
              ),
              format: 'uri',
            ),
            'prompt': ToolArgumentProperty.string(
              description:
                  'Instructions describing what to extract, summarize, inspect, compare, or transform from the page content.',
              localizedDescription: LocalizedToolText(
                english:
                    'Instructions describing what to extract, summarize, inspect, compare, or transform from the page content.',
                chinese: '描述要从网页内容中提取、总结、检查、比较或转换什么信息的指令。',
              ),
            ),
          },
          required: ['url', 'prompt'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final url = rawArguments['url'];
    if (url is! String || url.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_url',
        errorSummary: '读取网页失败：缺少有效链接',
      );
    }

    final prompt = rawArguments['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_prompt',
        errorSummary: '读取网页失败：缺少处理网页内容的 prompt',
      );
    }

    return ToolArgumentResolution.valid({
      'url': url.trim(),
      'prompt': prompt.trim(),
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _webpageFetcher(
      url: context.arguments['url'] as String,
      prompt: context.arguments['prompt'] as String,
    );
  }

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return [
      ChatMessage(
        text: _buildContextText(result),
        role: MessageRole.system,
        status: MessageStatus.completed,
      ),
    ];
  }

  String _buildContextText(ToolResult toolResult) {
    final buffer = StringBuffer()
      ..writeln('以下是工具 `${toolResult.toolName}` 的执行结果，请结合这些信息回答用户。')
      ..writeln('状态：${toolResult.status.name}');

    final payload = toolResult.payload;
    if (payload['title'] is String &&
        (payload['title'] as String).trim().isNotEmpty) {
      buffer.writeln('网页标题：${payload['title']}');
    }
    if (payload['url'] is String &&
        (payload['url'] as String).trim().isNotEmpty) {
      buffer.writeln('网页链接：${payload['url']}');
    }

    final prompt = (payload['prompt'] ?? '').toString().trim();
    if (prompt.isNotEmpty) {
      buffer.writeln('处理目标：$prompt');
    }

    final processedContent =
        (payload['processedContent'] ?? '').toString().trim();
    if (processedContent.isNotEmpty) {
      buffer.writeln(
        '处理结果：${_truncateContextText(processedContent, maxLength: 1200)}',
      );
    } else if (toolResult.summary.isNotEmpty) {
      buffer.writeln('结果摘要：${toolResult.summary}');
    }

    return buffer.toString().trim();
  }

  String _truncateContextText(
    String value, {
    required int maxLength,
  }) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }
}
