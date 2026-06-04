import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_result.dart';
import '../../models/workspace/resolved_workspace.dart';
import '../../services/file_tools/file_tool_write_service.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

class DeleteToolHandler extends ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'Delete',
        title: 'Delete',
        localizedTitle: LocalizedToolText(english: 'Delete', chinese: '删除文件'),
        descriptionForModel:
            'Use this when the user clearly wants content removed. It can delete a single file or recursively delete a directory inside the current workspace. Delete is a high-risk mutating action and must be used with great caution. Usually inspect the target with LS, Glob, Grep, or Read before deleting. Be especially careful with directory deletion and confirm the directory contents before proceeding. Any attempt to delete content outside the current workspace, or to delete the current workspace root itself, is strictly forbidden.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Use this when the user clearly wants content removed. It can delete a single file or recursively delete a directory inside the current workspace. Delete is a high-risk mutating action and must be used with great caution. Usually inspect the target with LS, Glob, Grep, or Read before deleting. Be especially careful with directory deletion and confirm the directory contents before proceeding. Any attempt to delete content outside the current workspace, or to delete the current workspace root itself, is strictly forbidden.',
          chinese:
              '当用户明确要求删除内容时使用。它可以删除单个文件，也可以递归删除当前 workspace 内的目录。Delete 属于高风险变更操作，请务必谨慎使用。通常应先用 LS、Glob、Grep 或 Read 确认目标后再删除；对于目录删除，必须特别确认目录所包含的文件内容。任何删除当前 workspace 之外内容，或删除当前 workspace 根目录本身的行为，都将被绝对禁止。',
        ),
        requiresConfirmation: true,
        isConcurrencySafe: false,
        supportedPlatforms: ['android', 'ios', 'macos', 'windows', 'linux'],
        argumentSchema: ToolArgumentSchema(
          properties: {
            'file_path': ToolArgumentProperty.string(
              description:
                  'Agent absolute or relative file or directory path to delete.',
              localizedDescription: LocalizedToolText(
                english:
                    'Agent absolute or relative file or directory path to delete.',
                chinese: '要删除的 agent 绝对路径或相对文件/目录路径。',
              ),
            ),
          },
          required: ['file_path'],
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
    if (filePath is! String || filePath.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_file_path',
        errorSummary: 'Delete failed: missing file_path',
      );
    }

    return ToolArgumentResolution.valid({
      'file_path': filePath.trim(),
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final fileTools = context.hostAdapters.fileTools;
    final writeService = fileTools?.writeService;
    if (fileTools == null || writeService == null) {
      return const ToolResult(
        toolName: 'Delete',
        status: ToolExecutionStatus.failure,
        summary: 'Delete failed: file tool adapters unavailable',
        errorMessage: 'unsupported_tool',
      );
    }

    final resolution = fileTools.pathPolicy.normalizeSandboxPath(
      context.arguments['file_path'] as String,
      cwd: context.cwd,
    );
    if (!resolution.isValid || resolution.relativePath == null) {
      return ToolResult(
        toolName: 'Delete',
        status: ToolExecutionStatus.failure,
        summary: 'Delete failed: invalid file path',
        errorMessage: resolution.errorCode ?? 'invalid_file_path',
      );
    }

    final workspace = context.workspace;
    if (workspace == null ||
        !_isWithinWorkspace(
          agentPath: resolution.agentPath!,
          workspace: workspace,
        )) {
      return ToolResult(
        toolName: 'Delete',
        status: ToolExecutionStatus.failure,
        summary: 'Delete failed: path outside current workspace',
        errorMessage: 'path_outside_workspace',
      );
    }

    if (_normalizeAgentPath(resolution.agentPath!) ==
        _normalizeAgentPath(workspace.fileRoot)) {
      return const ToolResult(
        toolName: 'Delete',
        status: ToolExecutionStatus.failure,
        summary: 'Delete failed: cannot delete current workspace root',
        errorMessage: 'cannot_delete_workspace_root',
      );
    }

    try {
      final outcome = await writeService.deletePath(
        relativePath: resolution.relativePath!,
      );
      return ToolResult(
        toolName: 'Delete',
        status: ToolExecutionStatus.success,
        summary: '已删除路径：${resolution.agentPath}',
        data: {
          'filePath': resolution.agentPath,
          'message': '已删除路径：${resolution.agentPath}',
          ...outcome.toJson(),
        },
      );
    } on FileToolWriteException catch (error) {
      return ToolResult(
        toolName: 'Delete',
        status: ToolExecutionStatus.failure,
        summary: '删除路径失败',
        data: {
          'filePath': resolution.agentPath,
          'message': '删除路径失败\n实际文件路径：${resolution.agentPath}',
        },
        errorMessage: error.code,
      );
    }
  }

  bool _isWithinWorkspace({
    required String agentPath,
    required ResolvedWorkspace workspace,
  }) {
    final normalizedAgentPath = _normalizeAgentPath(agentPath);
    final normalizedWorkspaceRoot = _normalizeAgentPath(workspace.fileRoot);
    if (normalizedAgentPath == normalizedWorkspaceRoot) {
      return true;
    }
    final workspacePrefix =
        normalizedWorkspaceRoot == '/' ? '/' : '$normalizedWorkspaceRoot/';
    return normalizedAgentPath.startsWith(workspacePrefix);
  }

  String _normalizeAgentPath(String pathValue) {
    final trimmed = pathValue.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) {
      return '/';
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }
}
