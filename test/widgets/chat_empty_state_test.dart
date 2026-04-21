import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/widgets/chat_empty_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('featured debug cases map to empty state suggestions', () {
    const cases = <DebugTestCase>[
      DebugTestCase(
        id: 'plain-answer',
        group: 'tool-call',
        title: '纯文本直答',
        summary: '验证无需工具时直接回答。',
        prompt: '用一句话解释什么是 SQLite',
        tags: ['agent-loop'],
        featured: true,
        enabled: true,
        setup: _emptySetup,
        checkpoints: ['finalAnswer'],
        assertions: _completedAssertions,
      ),
      DebugTestCase(
        id: 'confirmation',
        group: 'confirmation',
        title: '需要确认',
        summary: '验证副作用工具确认暂停。',
        prompt: '提醒我今晚 8 点提交周报',
        tags: ['confirmation'],
        featured: true,
        enabled: true,
        setup: _emptySetup,
        checkpoints: ['tool:create_reminder:awaiting_confirmation'],
        assertions: DebugTestCaseAssertions(
          endStatus: ['awaitingToolConfirmation'],
          mustContainEvents: [],
          mustNotContainEvents: [],
          mustContainErrorCodes: [],
          mustContainAnyErrorCodes: [],
          forbidErrorCodes: [],
          finalAnswerContainsAll: [],
          finalFileContains: [],
          finalFileUnchanged: [],
          mustNotFalseClaimWriteSuccess: false,
          mustNotFalseClaimReadSuccess: false,
          mustNotHang: true,
        ),
      ),
      DebugTestCase(
        id: 'disabled',
        group: 'failure',
        title: '已停用案例',
        summary: '不应该进入空状态。',
        prompt: 'disabled',
        tags: ['legacy'],
        featured: false,
        enabled: false,
        setup: _emptySetup,
        checkpoints: ['tool:fetch_webpage:failure'],
        assertions: DebugTestCaseAssertions(
          endStatus: ['failed'],
          mustContainEvents: [],
          mustNotContainEvents: [],
          mustContainErrorCodes: [],
          mustContainAnyErrorCodes: [],
          forbidErrorCodes: [],
          finalAnswerContainsAll: [],
          finalFileContains: [],
          finalFileUnchanged: [],
          mustNotFalseClaimWriteSuccess: false,
          mustNotFalseClaimReadSuccess: true,
          mustNotHang: true,
        ),
      ),
    ];

    final suggestions = buildChatEmptySuggestionsFromCases(cases);

    expect(suggestions, hasLength(2));
    expect(suggestions.map((item) => item.label), ['纯文本直答', '需要确认']);
    expect(
      suggestions.map((item) => item.prompt),
      ['用一句话解释什么是 SQLite', '提醒我今晚 8 点提交周报'],
    );
  });
}

const _emptySetup = DebugTestCaseSetup(
  historyMessages: [],
  files: [],
  mutationsAfterCheckpoints: [],
);

const _completedAssertions = DebugTestCaseAssertions(
  endStatus: ['completed'],
  mustContainEvents: [],
  mustNotContainEvents: [],
  mustContainErrorCodes: [],
  mustContainAnyErrorCodes: [],
  forbidErrorCodes: [],
  finalAnswerContainsAll: [],
  finalFileContains: [],
  finalFileUnchanged: [],
  mustNotFalseClaimWriteSuccess: false,
  mustNotFalseClaimReadSuccess: false,
  mustNotHang: true,
);
