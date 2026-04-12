import '../../models/chat_message.dart';
import '../../models/tool/tool_definition.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Handles the complete runtime behavior for the `save_note` tool.
class SaveNoteToolHandler implements ToolHandler {
  SaveNoteToolHandler({
    required NoteSaver noteSaver,
  }) : _noteSaver = noteSaver;

  final NoteSaver _noteSaver;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'save_note',
        title: '保存笔记',
        description: '将当前内容保存为本地笔记。',
        parameters: {
          'title': 'string',
          'content': 'string',
          'folder': 'string?',
        },
        requiresConfirmation: true,
        riskLevel: 'medium',
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final title = rawArguments['title'];
    final content = rawArguments['content'];
    if (title is! String || title.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_title',
        errorSummary: '保存笔记失败：缺少有效标题',
      );
    }
    if (content is! String || content.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_content',
        errorSummary: '保存笔记失败：缺少有效内容',
      );
    }

    final folder = rawArguments['folder'];
    return ToolArgumentResolution.valid({
      'title': title.trim(),
      'content': content.trim(),
      if (folder is String && folder.trim().isNotEmpty) 'folder': folder.trim(),
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _noteSaver(
      title: context.arguments['title'] as String,
      content: context.arguments['content'] as String,
      folder: context.arguments['folder'] as String?,
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

    if (toolResult.summary.isNotEmpty) {
      buffer.writeln('结果摘要：${toolResult.summary}');
    }

    final payload = toolResult.payload;
    if (payload['title'] is String) {
      buffer.writeln('笔记标题：${payload['title']}');
    }
    if (payload['folder'] is String && (payload['folder'] as String).trim().isNotEmpty) {
      buffer.writeln('笔记目录：${payload['folder']}');
    }

    return buffer.toString().trim();
  }
}
