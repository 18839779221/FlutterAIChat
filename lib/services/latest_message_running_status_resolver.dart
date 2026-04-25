import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';

/// UI-facing running tail text for the latest visible message in the current turn.
class LatestMessageRunningStatusPresentation {
  final String text;

  const LatestMessageRunningStatusPresentation({
    required this.text,
  });
}

/// Resolves the lightweight status tail shown under the latest visible message.
///
/// The resolver keeps wording focused on the system action currently happening,
/// and degrades to a generic tool-running label when multiple tools appear to be
/// active at the same time.
class LatestMessageRunningStatusResolver {
  const LatestMessageRunningStatusResolver();

  LatestMessageRunningStatusPresentation? resolve({
    required List<ChatMessage> messages,
    required ChatSendPhase sendPhase,
  }) {
    if (sendPhase == ChatSendPhase.idle || messages.isEmpty) {
      return null;
    }

    final currentTurnMessages = _currentTurnMessages(messages);
    if (currentTurnMessages.isEmpty) {
      return null;
    }

    switch (sendPhase) {
      case ChatSendPhase.idle:
        return null;
      case ChatSendPhase.preparing:
        return LatestMessageRunningStatusPresentation(
          text: _hasAssistantOutput(currentTurnMessages)
              ? '正在规划下一步'
              : '正在请求模型',
        );
      case ChatSendPhase.awaitingConfirmation:
        return const LatestMessageRunningStatusPresentation(
          text: '等待工具确认',
        );
      case ChatSendPhase.executingTool:
        final executingToolText = _resolveExecutingToolText(currentTurnMessages);
        return LatestMessageRunningStatusPresentation(
          text: executingToolText ??
              (_hasTrailingToolResult(currentTurnMessages)
                  ? '正在规划下一步'
                  : '正在等待结果'),
        );
      case ChatSendPhase.streamingResponse:
        return const LatestMessageRunningStatusPresentation(
          text: '正在生成回复',
        );
    }
  }

  List<ChatMessage> _currentTurnMessages(List<ChatMessage> messages) {
    final lastUserIndex = messages.lastIndexWhere((message) => message.isUser);
    if (lastUserIndex == -1) {
      return List<ChatMessage>.from(messages, growable: false);
    }
    return List<ChatMessage>.from(
      messages.sublist(lastUserIndex),
      growable: false,
    );
  }

  bool _hasAssistantOutput(List<ChatMessage> currentTurnMessages) {
    return currentTurnMessages.any((message) => message.isAssistant);
  }

  bool _hasTrailingToolResult(List<ChatMessage> currentTurnMessages) {
    final trailingToolMessages = _collectTrailingToolMessages(currentTurnMessages);
    return trailingToolMessages.any(
      (message) => message.contentType == MessageContentType.toolResult,
    );
  }

  String? _resolveExecutingToolText(List<ChatMessage> currentTurnMessages) {
    final trailingToolMessages = _collectTrailingToolMessages(currentTurnMessages);
    if (trailingToolMessages.isEmpty) {
      return null;
    }

    final pendingResultsByTool = <String, int>{};
    final activeToolNames = <String>[];

    for (final message in trailingToolMessages.reversed) {
      if (message.contentType == MessageContentType.toolResult) {
        final toolName = _readToolResultName(message);
        if (toolName == null) {
          continue;
        }
        pendingResultsByTool.update(toolName, (count) => count + 1, ifAbsent: () => 1);
        continue;
      }

      final invocation = _readToolInvocation(message);
      if (invocation == null || !_isInvocationActive(invocation.status)) {
        continue;
      }
      final toolName = invocation.toolName.trim();
      if (toolName.isEmpty) {
        continue;
      }
      final pendingCount = pendingResultsByTool[toolName] ?? 0;
      if (pendingCount > 0) {
        pendingResultsByTool[toolName] = pendingCount - 1;
        continue;
      }
      activeToolNames.add(toolName);
    }

    if (activeToolNames.isEmpty) {
      return null;
    }
    if (activeToolNames.length > 1) {
      return '正在执行工具';
    }

    return _toolStatusText(activeToolNames.single) ?? '正在执行工具';
  }

  List<ChatMessage> _collectTrailingToolMessages(
    List<ChatMessage> currentTurnMessages,
  ) {
    final collected = <ChatMessage>[];
    for (var index = currentTurnMessages.length - 1; index >= 0; index -= 1) {
      final message = currentTurnMessages[index];
      if (!message.isAssistant) {
        break;
      }
      if (message.contentType != MessageContentType.toolInvocation &&
          message.contentType != MessageContentType.actionConfirmation &&
          message.contentType != MessageContentType.toolResult) {
        break;
      }
      collected.add(message);
    }
    return collected.reversed.toList(growable: false);
  }

  ToolInvocation? _readToolInvocation(ChatMessage message) {
    final payload = message.payloadJson;
    if (payload == null) {
      return null;
    }
    try {
      return ToolInvocation.fromJson(payload);
    } catch (_) {
      return null;
    }
  }

  String? _readToolResultName(ChatMessage message) {
    final payload = message.payloadJson;
    if (payload == null) {
      return null;
    }
    try {
      final toolName = ToolResult.fromJson(payload).toolName.trim();
      return toolName.isEmpty ? null : toolName;
    } catch (_) {
      return null;
    }
  }

  bool _isInvocationActive(ToolInvocationStatus status) {
    switch (status) {
      case ToolInvocationStatus.awaitingConfirmation:
      case ToolInvocationStatus.running:
        return true;
      case ToolInvocationStatus.proposed:
      case ToolInvocationStatus.cancelled:
        return false;
    }
  }

  String? _toolStatusText(String toolName) {
    switch (toolName.trim()) {
      case 'web_search':
        return '正在联网搜索';
      case 'fetch_webpage':
        return '正在读取网页';
      case 'Read':
        return '正在读取文件';
      case 'LS':
        return '正在列出目录';
      case 'Grep':
        return '正在搜索文件内容';
      case 'Glob':
        return '正在查找文件';
      default:
        return null;
    }
  }
}
