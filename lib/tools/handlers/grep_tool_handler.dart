import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/tool_result.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

class GrepToolHandler implements ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'Grep',
        title: '搜索文件内容',
        description: '按关键字或正则在沙箱文件内容中搜索。',
        descriptionForModel:
            '当你知道某个符号、关键字、短语或正则模式，但还不知道它出现在哪个文件中时使用。优先用于内容搜索，而不是读取完整文件。',
        category: ToolCategory.retrieval,
        capabilities: [ToolCapability.fileDiscovery],
        supportedPlatforms: ['android', 'ios', 'macos', 'windows', 'linux'],
        argumentSchema: ToolArgumentSchema(
          properties: {
            'pattern': ToolArgumentProperty.string(
              description: '要搜索的正则表达式或关键字。',
            ),
            'path': ToolArgumentProperty.string(
              description: '可选的沙箱相对起始目录。',
            ),
            'glob': ToolArgumentProperty.string(
              description: '可选的文件路径过滤 glob 模式。',
            ),
            'output_mode': ToolArgumentProperty.string(
              description: '输出模式，可选 files_with_matches、content、count。',
              enumValues: ['files_with_matches', 'content', 'count'],
            ),
            'head_limit': ToolArgumentProperty.integer(
              description: 'content 模式下最多返回多少条命中。',
            ),
            'multiline': ToolArgumentProperty(
              type: 'boolean',
              description: '是否允许模式跨多行匹配。',
            ),
            'case_insensitive': ToolArgumentProperty(
              type: 'boolean',
              description: '是否忽略大小写。',
            ),
            'line_numbers': ToolArgumentProperty(
              type: 'boolean',
              description: 'content 模式下是否返回行号。',
            ),
          },
          required: ['pattern'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final pattern = rawArguments['pattern'];
    if (pattern is! String || pattern.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_pattern',
        errorSummary: 'Grep failed: missing pattern',
      );
    }
    final outputMode = rawArguments['output_mode'];
    final normalizedOutputMode =
        outputMode is String && outputMode.trim().isNotEmpty
            ? outputMode.trim()
            : 'files_with_matches';
    return ToolArgumentResolution.valid({
      'pattern': pattern.trim(),
      'output_mode': normalizedOutputMode,
      if (rawArguments['path'] is String &&
          (rawArguments['path'] as String).trim().isNotEmpty)
        'path': (rawArguments['path'] as String).trim(),
      if (rawArguments['glob'] is String &&
          (rawArguments['glob'] as String).trim().isNotEmpty)
        'glob': (rawArguments['glob'] as String).trim(),
      'head_limit': rawArguments['head_limit'] is num
          ? (rawArguments['head_limit'] as num).toInt().clamp(1, 200)
          : 20,
      'multiline': rawArguments['multiline'] == true,
      'case_insensitive': rawArguments['case_insensitive'] == true,
      'line_numbers': rawArguments['line_numbers'] == true,
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final fileTools = context.hostAdapters.fileTools;
    if (fileTools == null) {
      return const ToolResult(
        toolName: 'Grep',
        status: ToolExecutionStatus.failure,
        summary: 'Grep failed: file tool adapters unavailable',
        errorMessage: 'unsupported_tool',
      );
    }

    final payload = await fileTools.discoveryService.grep(
      pattern: context.arguments['pattern'] as String,
      pathValue: context.arguments['path'] as String?,
      glob: context.arguments['glob'] as String?,
      outputMode:
          context.arguments['output_mode'] as String? ?? 'files_with_matches',
      headLimit: context.arguments['head_limit'] as int? ?? 20,
      multiline: context.arguments['multiline'] == true,
      caseInsensitive: context.arguments['case_insensitive'] == true,
      lineNumbers: context.arguments['line_numbers'] == true,
    );
    return ToolResult(
      toolName: 'Grep',
      status: ToolExecutionStatus.success,
      summary: '已完成文件内容搜索',
      data: {
        'pattern': context.arguments['pattern'],
        ...payload,
      },
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
