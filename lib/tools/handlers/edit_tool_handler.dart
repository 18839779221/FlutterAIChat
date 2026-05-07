import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_result.dart';
import '../../services/file_tools/file_tool_session_guard.dart';
import '../../services/file_tools/file_tool_write_service.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

class EditToolHandler extends ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'Edit',
        title: 'Edit',
        localizedTitle: LocalizedToolText(english: 'Edit', chinese: '编辑文件'),
        descriptionForModel:
            'Use this for small, precise text replacements in an existing file. Usually Read first, then Edit. If old_string is not unique in the file, provide more context or explicitly use replace_all. Edit is a mutating action and requires confirmation.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Use this for small, precise text replacements in an existing file. Usually Read first, then Edit. If old_string is not unique in the file, provide more context or explicitly use replace_all. Edit is a mutating action and requires confirmation.',
          chinese:
              '当需要对已有文件做小范围、精确的文本替换时使用。通常应先 Read，再 Edit。若 old_string 在文件中不唯一，应补充更多上下文，或明确使用 replace_all。Edit 属于写操作，需要确认。',
        ),
        supportedPlatforms: ['android', 'ios', 'macos', 'windows', 'linux'],
        requiresConfirmation: true,
        argumentSchema: ToolArgumentSchema(
          properties: {
            'file_path': ToolArgumentProperty.string(
              description: 'Relative sandbox file path to edit.',
              localizedDescription: LocalizedToolText(
                english: 'Relative sandbox file path to edit.',
                chinese: '要编辑的沙箱相对文件路径。',
              ),
            ),
            'old_string': ToolArgumentProperty.string(
              description:
                  'Exact existing text in the file that should be replaced.',
              localizedDescription: LocalizedToolText(
                english:
                    'Exact existing text in the file that should be replaced.',
                chinese: '文件中当前存在、将被替换的精确文本。',
              ),
            ),
            'new_string': ToolArgumentProperty.string(
              description: 'Replacement text to write instead.',
              localizedDescription: LocalizedToolText(
                english: 'Replacement text to write instead.',
                chinese: '替换后的新文本。',
              ),
            ),
            'replace_all': ToolArgumentProperty(
              type: 'boolean',
              description: 'Whether to replace all matches instead of just one.',
              localizedDescription: LocalizedToolText(
                english:
                    'Whether to replace all matches instead of just one.',
                chinese: '是否替换所有匹配项。',
              ),
            ),
          },
          required: ['file_path', 'old_string', 'new_string'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final filePath = rawArguments['file_path'];
    final oldString = rawArguments['old_string'];
    final newString = rawArguments['new_string'];
    if (filePath is! String || filePath.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_file_path',
        errorSummary: 'Edit failed: missing file_path',
      );
    }
    if (oldString is! String || oldString.isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_old_string',
        errorSummary: 'Edit failed: missing old_string',
      );
    }
    if (newString is! String) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_new_string',
        errorSummary: 'Edit failed: missing new_string',
      );
    }
    return ToolArgumentResolution.valid({
      'file_path': filePath.trim(),
      'old_string': oldString,
      'new_string': newString,
      'replace_all': rawArguments['replace_all'] == true,
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final fileTools = context.hostAdapters.fileTools;
    final writeService = fileTools?.writeService;
    if (fileTools == null || writeService == null) {
      return const ToolResult(
        toolName: 'Edit',
        status: ToolExecutionStatus.failure,
        summary: 'Edit failed: file tool adapters unavailable',
        errorMessage: 'unsupported_tool',
      );
    }

    final resolution = fileTools.pathPolicy.normalizeSandboxPath(
      context.arguments['file_path'] as String,
    );
    if (!resolution.isValid || resolution.relativePath == null) {
      return ToolResult(
        toolName: 'Edit',
        status: ToolExecutionStatus.failure,
        summary: 'Edit failed: invalid file path',
        errorMessage: resolution.errorCode ?? 'invalid_file_path',
      );
    }

    try {
      final outcome = await writeService.editFile(
        relativePath: resolution.relativePath!,
        oldString: context.arguments['old_string'] as String,
        newString: context.arguments['new_string'] as String,
        replaceAll: context.arguments['replace_all'] == true,
      );
      return ToolResult(
        toolName: 'Edit',
        status: ToolExecutionStatus.success,
        summary: '已编辑文件：${resolution.relativePath}',
        data: {
          'message': '已编辑文件：${resolution.relativePath}',
          ...outcome.toJson(),
        },
      );
    } on FileToolGuardException catch (error) {
      return ToolResult(
        toolName: 'Edit',
        status: ToolExecutionStatus.failure,
        summary: '编辑文件失败：文件未读取或状态已过期',
        data: {
          'filePath': resolution.relativePath,
          'message':
              '编辑文件失败：文件未读取或状态已过期\n实际文件路径：${resolution.relativePath}',
        },
        errorMessage: error.code,
      );
    } on FileToolWriteException catch (error) {
      return ToolResult(
        toolName: 'Edit',
        status: ToolExecutionStatus.failure,
        summary: '编辑文件失败',
        data: {
          'filePath': resolution.relativePath,
          'message': '编辑文件失败\n实际文件路径：${resolution.relativePath}',
        },
        errorMessage: error.code,
      );
    }
  }

}
