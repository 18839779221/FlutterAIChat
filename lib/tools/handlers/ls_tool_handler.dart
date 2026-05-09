import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_result.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

class LsToolHandler extends ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'LS',
        title: 'LS',
        localizedTitle: LocalizedToolText(english: 'LS', chinese: '列出目录'),
        descriptionForModel:
            'Use this to inspect directory structure, verify that a path exists, or see the direct files and subdirectories under a directory. It does not read file contents recursively.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Use this to inspect directory structure, verify that a path exists, or see the direct files and subdirectories under a directory. It does not read file contents recursively.',
          chinese:
              '当你想确认目录结构、验证路径是否存在、或查看某个目录下有哪些直接文件和子目录时使用。不会递归读取文件内容。',
        ),
        isConcurrencySafe: true,
        supportedPlatforms: ['android', 'ios', 'macos', 'windows', 'linux'],
        argumentSchema: ToolArgumentSchema(
          properties: {
            'path': ToolArgumentProperty.string(
              description: 'Relative sandbox directory path to list.',
              localizedDescription: LocalizedToolText(
                english: 'Relative sandbox directory path to list.',
                chinese: '要列出的沙箱相对目录路径。',
              ),
            ),
          },
          required: ['path'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final path = rawArguments['path'];
    if (path is! String || path.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_path',
        errorSummary: 'LS failed: missing path',
      );
    }
    return ToolArgumentResolution.valid({
      'path': path.trim(),
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final fileTools = context.hostAdapters.fileTools;
    if (fileTools == null) {
      return const ToolResult(
        toolName: 'LS',
        status: ToolExecutionStatus.failure,
        summary: 'LS failed: file tool adapters unavailable',
        errorMessage: 'unsupported_tool',
      );
    }

    final entries = await fileTools.discoveryService.list(
      pathValue: context.arguments['path'] as String,
    );
    return ToolResult(
      toolName: 'LS',
      status: ToolExecutionStatus.success,
      summary: '已列出目录：${context.arguments['path']}',
      data: {
        'path': context.arguments['path'],
        'entries': entries.map((item) => item.toJson()).toList(),
      },
    );
  }

}
