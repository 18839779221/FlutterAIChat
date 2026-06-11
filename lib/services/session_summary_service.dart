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
Your task is to create a detailed summary of this conversation. This summary will be placed at the start of a continuing session; newer messages that build on this context will follow after your summary.

Before providing your final summary, wrap your analysis in <analysis> tags to organize your thoughts and ensure you've covered all necessary points. In your analysis process:

1. Analyze the conversation chronologically. For each section thoroughly identify:
   - The user's explicit requests and intents
   - Your approach to addressing the user's requests
   - Key decisions, technical concepts, and important working patterns
   - Specific details such as file names, important paths, tool conclusions, configurations, and outputs
   - Errors that you ran into and how you fixed them
   - Specific user feedback, especially where the user told you to do something differently
2. Double-check for technical accuracy and completeness before producing the final summary.

Your entire response must be plain text and follow this structure exactly:

<analysis>
[Your internal working notes]
</analysis>

<summary>
1. Primary Request and Intent:
   [Detailed description]

2. Key Technical Concepts:
   - [Concept 1]
   - [Concept 2]

3. Files and Code Sections:
   - [File or important working surface]
   - [Why it matters]
   - [Important details]
   - If the current task does not involve code files, use this section to record key tool conclusions, UI surfaces, artifact paths, config objects, or other important work surfaces needed to continue accurately.

4. Errors and fixes:
   - [Error and fix]

5. Problem Solving:
   [Solved problems and ongoing troubleshooting]

6. All user messages:
   - [List ALL non-tool-result user messages]

7. Pending Tasks:
   - [Pending work]

8. Work Completed:
   [What was completed by the end of this portion]

9. Context for Continuing Work:
   [What the next continuation needs to know]
</summary>
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

    final generated = (await generator(summaryPromptMessages)).trim();
    final summaryText = _extractSummaryBody(generated);
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

  String _extractSummaryBody(String generated) {
    final summaryMatch = RegExp(
      r'<summary>\s*([\s\S]*?)\s*</summary>',
      caseSensitive: false,
    ).firstMatch(generated);
    if (summaryMatch != null) {
      return summaryMatch.group(1)?.trim() ?? '';
    }
    return generated.trim();
  }

}
