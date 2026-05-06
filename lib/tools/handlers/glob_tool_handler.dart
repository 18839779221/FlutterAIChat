import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_result.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

class GlobToolHandler implements ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'Glob',
        title: 'Glob',
        localizedTitle: LocalizedToolText(english: 'Glob', chinese: '查找文件'),
        descriptionForModel:
            'Use this when you know the approximate file name, extension, or path pattern, such as finding all .md or .json files or a specific file under a directory. It only discovers paths and does not read file contents.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Use this when you know the approximate file name, extension, or path pattern, such as finding all .md or .json files or a specific file under a directory. It only discovers paths and does not read file contents.',
          chinese:
              '当你知道目标文件的大致文件名、扩展名或路径模式时使用，例如查找所有 .md、.json 或某个目录下的特定文件。它只做路径发现，不读取文件内容。',
        ),
        isConcurrencySafe: true,
        supportedPlatforms: ['android', 'ios', 'macos', 'windows', 'linux'],
        argumentSchema: ToolArgumentSchema(
          properties: {
            'pattern': ToolArgumentProperty.string(
              description: 'Glob pattern used to discover matching files.',
              localizedDescription: LocalizedToolText(
                english: 'Glob pattern used to discover matching files.',
                chinese: '用于查找文件的 glob 模式。',
              ),
            ),
            'path': ToolArgumentProperty.string(
              description: 'Optional relative sandbox start directory.',
              localizedDescription: LocalizedToolText(
                english: 'Optional relative sandbox start directory.',
                chinese: '可选的沙箱相对起始目录。',
              ),
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
        errorSummary: 'Glob failed: missing pattern',
      );
    }
    final path = rawArguments['path'];
    return ToolArgumentResolution.valid({
      'pattern': pattern.trim(),
      if (path is String && path.trim().isNotEmpty) 'path': path.trim(),
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final fileTools = context.hostAdapters.fileTools;
    if (fileTools == null) {
      return const ToolResult(
        toolName: 'Glob',
        status: ToolExecutionStatus.failure,
        summary: 'Glob failed: file tool adapters unavailable',
        errorMessage: 'unsupported_tool',
      );
    }

    final matches = await fileTools.discoveryService.glob(
      pattern: context.arguments['pattern'] as String,
      pathValue: context.arguments['path'] as String?,
    );
    return ToolResult(
      toolName: 'Glob',
      status: ToolExecutionStatus.success,
      summary: '已查找到 ${matches.length} 个文件',
      data: {
        'pattern': context.arguments['pattern'],
        'matches': matches,
      },
    );
  }

}
