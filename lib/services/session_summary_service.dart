import '../models/chat_message.dart';
import 'chat_service.dart';
import 'session_token_budget_service.dart';

class SessionSummaryResult {
  final String summaryText;
  final int estimatedTokens;

  const SessionSummaryResult({
    required this.summaryText,
    required this.estimatedTokens,
  });
}

typedef SessionSummaryGenerator = Future<String> Function(
  List<ChatMessage> messages,
);

class SessionSummaryService {
  static const String summaryInstructionPrompt = '''
请将以下会话历史整理为稳定摘要，必须使用以下栏目且不要输出 Markdown 代码块：
当前目标：
已确认事实：
用户偏好/限制：
已确认决策：
已否决方案：
文件/工具/代码结论：
错误与修正：
未完成事项：
当前进展：
下一步：

要求：
1. 只保留后续继续工作需要的信息。
2. 不要输出原始 JSON 或 payload。
3. 如果某栏目暂无内容，写“无”。
''';

  SessionSummaryService({
    ChatService? chatService,
    SessionSummaryGenerator? summaryGenerator,
    SessionTokenBudgetService? tokenBudgetService,
  })  : _chatService = chatService,
        _summaryGenerator = summaryGenerator,
        _tokenBudgetService = tokenBudgetService ?? SessionTokenBudgetService();

  final ChatService? _chatService;
  final SessionSummaryGenerator? _summaryGenerator;
  final SessionTokenBudgetService _tokenBudgetService;

  Future<SessionSummaryResult> summarize({
    required int groupId,
    required List<ChatMessage> projectedHistory,
  }) async {
    return summarizeHistory(
      previousSummary: null,
      historicalMessages: projectedHistory,
    );
  }

  Future<SessionSummaryResult> summarizeHistory({
    String? previousSummary,
    required List<ChatMessage> historicalMessages,
  }) async {
    final generator = _resolveGenerator();
    final summaryPromptMessages = [
        ChatMessage(
          text: summaryInstructionPrompt,
          role: MessageRole.system,
          status: MessageStatus.completed,
        ),
      if ((previousSummary ?? '').trim().isNotEmpty)
        ChatMessage(
          text: previousSummary!.trim(),
          role: MessageRole.system,
          status: MessageStatus.completed,
        ),
      ...historicalMessages,
    ];

    final summaryText = (await generator(summaryPromptMessages)).trim();
    if (summaryText.isEmpty) {
      throw StateError('session_summary_empty');
    }

    return SessionSummaryResult(
      summaryText: summaryText,
      estimatedTokens: _tokenBudgetService.estimateTextTokens(summaryText),
    );
  }

  SessionSummaryGenerator _resolveGenerator() {
    final summaryGenerator = _summaryGenerator;
    if (summaryGenerator != null) {
      return summaryGenerator;
    }
    final chatService = _chatService;
    if (chatService == null) {
      throw StateError('SessionSummaryService requires a summary generator');
    }
    return chatService.llm.summarizeConversation;
  }

}
