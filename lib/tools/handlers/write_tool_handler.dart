import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_result.dart';
import '../../services/file_tools/file_tool_session_guard.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

class WriteToolHandler extends ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'Write',
        title: 'Write',
        localizedTitle: LocalizedToolText(english: 'Write', chinese: '写入文件'),
        descriptionForModel:
            'Use this when the user clearly wants a new file or a full-file rewrite. For small edits to an existing file, prefer Edit. Write is a high-risk mutating action and requires confirmation.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Use this when the user clearly wants a new file or a full-file rewrite. For small edits to an existing file, prefer Edit. Write is a high-risk mutating action and requires confirmation.',
          chinese:
              '当用户明确要求创建新文件，或需要整文件重写时使用。对于已有文件的小范围修改，优先使用 Edit。Write 属于高风险写操作，需要确认。',
        ),
        isConcurrencySafe: false,
        supportedPlatforms: ['android', 'ios', 'macos', 'windows', 'linux'],
        requiresConfirmation: true,
        argumentSchema: ToolArgumentSchema(
          properties: {
            'file_path': ToolArgumentProperty.string(
              description: 'Agent absolute or relative file path to create or overwrite.',
              localizedDescription: LocalizedToolText(
                english:
                    'Agent absolute or relative file path to create or overwrite.',
                chinese: '要创建或覆盖的 agent 绝对路径或相对文件路径。',
              ),
            ),
            'content': ToolArgumentProperty.string(
              description: 'Full file content to write.',
              localizedDescription: LocalizedToolText(
                english: 'Full file content to write.',
                chinese: '要写入的完整文件内容。',
              ),
            ),
          },
          required: ['file_path', 'content'],
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
    final content = rawArguments['content'];
    if (filePath is! String || filePath.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_file_path',
        errorSummary: 'Write failed: missing file_path',
      );
    }
    if (content is! String) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_content',
        errorSummary: 'Write failed: missing content',
      );
    }
    return ToolArgumentResolution.valid({
      'file_path': filePath.trim(),
      'content': content,
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final fileTools = context.hostAdapters.fileTools;
    final writeService = fileTools?.writeService;
    var effectiveAgentPath =
        (context.arguments['file_path'] as String).trim().replaceAll('\\', '/');
    if (fileTools == null || writeService == null) {
      return const ToolResult(
        toolName: 'Write',
        status: ToolExecutionStatus.failure,
        summary: 'Write failed: file tool adapters unavailable',
        errorMessage: 'unsupported_tool',
      );
    }

    final resolution = fileTools.pathPolicy.normalizeSandboxPath(
      context.arguments['file_path'] as String,
      cwd: context.cwd,
    );
    if (!resolution.isValid || resolution.relativePath == null) {
      return ToolResult(
        toolName: 'Write',
        status: ToolExecutionStatus.failure,
        summary: 'Write failed: invalid file path',
        errorMessage: resolution.errorCode ?? 'invalid_file_path',
      );
    }

    try {
      var effectiveResolution = resolution;
      var workspaceReminder = '';
      var workspaceId = context.workspace?.workspaceId;
      if (context.workspace?.isDefault == true) {
        final existingFile = fileTools.rootService
            .resolveFile(effectiveResolution.relativePath!)
            .existsSync();
        if (!existingFile) {
          final transition = await context
              .hostAdapters.workspace
              ?.ensureWorkspaceForLongLivedOutput(context.groupId);
          if (transition != null) {
            workspaceReminder = transition.reminderMessage ?? '';
            workspaceId = transition.workspace.workspaceId;
            effectiveResolution = fileTools.pathPolicy.normalizeSandboxPath(
              context.arguments['file_path'] as String,
              cwd: transition.workspace.fileRoot,
            );
          }
        }
      }
      final outcome = await writeService.writeFile(
        relativePath: effectiveResolution.relativePath!,
        content: context.arguments['content'] as String,
      );
      effectiveAgentPath = effectiveResolution.agentPath ?? effectiveAgentPath;
      return ToolResult(
        toolName: 'Write',
        status: ToolExecutionStatus.success,
        summary: '已写入文件：$effectiveAgentPath',
        data: {
          'message': '已写入文件：$effectiveAgentPath',
          if (workspaceId != null) 'workspaceId': workspaceId,
          if (workspaceReminder.isNotEmpty)
            'workspaceChangeReminder': workspaceReminder,
          ...outcome.toJson(),
        },
      );
    } on FileToolGuardException catch (error) {
      return ToolResult(
        toolName: 'Write',
        status: ToolExecutionStatus.failure,
        summary: '写入文件失败：文件未读取或状态已过期',
        data: {
          'filePath': effectiveAgentPath,
          'message':
              '写入文件失败：文件未读取或状态已过期\n实际文件路径：$effectiveAgentPath',
        },
        errorMessage: error.code,
      );
    }
  }

}
