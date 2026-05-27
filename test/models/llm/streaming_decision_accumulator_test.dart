import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingDecisionAccumulator', () {
    test('aggregates terminal assistant text and reasoning', () {
      final accumulator = StreamingDecisionAccumulator();

      _consumeAll(accumulator, [
        const StreamingMessageStartEvent(messageId: 'm1'),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          blockType: StreamingContentBlockType.thinking,
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          deltaType: StreamingContentDeltaType.thinking,
          value: '先分析',
        ),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          blockType: StreamingContentBlockType.text,
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '最终',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '答案',
        ),
        const StreamingMessageStopEvent(messageId: 'm1'),
      ]);

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, '最终答案');
      expect(decision.visibleReasoning, '先分析');
      expect(decision.isTerminal, isTrue);
    });

    test('preserves whitespace-only deltas inside assistant markdown', () {
      final accumulator = StreamingDecisionAccumulator();

      _consumeAll(accumulator, [
        const StreamingMessageStartEvent(messageId: 'm1'),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          blockType: StreamingContentBlockType.text,
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '# 标题',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '\n\n',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '```dart',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '\n',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: 'ListView.builder();',
        ),
        const StreamingMessageStopEvent(messageId: 'm1'),
      ]);

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(
        decision!.assistantMessage,
        '# 标题\n\n```dart\nListView.builder();',
      );
    });

    test('aggregates completed tool call arguments by tool call index', () {
      final accumulator = StreamingDecisionAccumulator();

      _consumeAll(accumulator, [
        const StreamingMessageStartEvent(messageId: 'm1'),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_1',
          toolName: 'write_file',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: '{"path":"a.txt",',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: '"content":"hello"}',
        ),
        const StreamingContentBlockStopEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
        ),
        const StreamingMessageStopEvent(messageId: 'm1'),
      ]);

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.providerCallId, 'call_1');
      expect(decision.toolCalls.single.toolName, 'write_file');
      expect(decision.toolCalls.single.arguments, {
        'path': 'a.txt',
        'content': 'hello',
      });
      expect(decision.isTerminal, isFalse);
    });

    test('exposes structured snapshot for streaming tool call arguments', () {
      final accumulator = StreamingDecisionAccumulator();

      _consumeAll(accumulator, [
        const StreamingMessageStartEvent(messageId: 'm1'),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_artifact_1',
          toolName: 'create_artifact',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: '{"source":"<div>Hello',
        ),
      ]);

      final snapshot = accumulator.currentSnapshot();

      expect(snapshot.blocks, hasLength(1));
      expect(snapshot.blocks.single.type, StreamingContentBlockType.toolUse);
      expect(snapshot.blocks.single.toolUseId, 'call_artifact_1');
      expect(snapshot.blocks.single.toolName, 'create_artifact');
      expect(snapshot.blocks.single.text, contains('<div>Hello'));
      expect(snapshot.blocks.single.isStopped, isFalse);
    });

    test(
        'keeps anonymous argument deltas attached to latest unfinished indexed tool call',
        () {
      final accumulator = StreamingDecisionAccumulator();

      _consumeAll(accumulator, [
        const StreamingMessageStartEvent(messageId: 'm1'),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_artifact_2',
          toolName: 'create_artifact',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value:
              '{"id":"demo","type":"html","title":"Demo","source":"<div>Hello</div>"}',
        ),
        const StreamingMessageStopEvent(messageId: 'm1'),
      ]);

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.providerCallId, 'call_artifact_2');
      expect(decision.toolCalls.single.toolName, 'create_artifact');
      expect(
        decision.toolCalls.single.arguments['source'],
        '<div>Hello</div>',
      );
    });

    test('drops invalid completed tool call arguments instead of failing decision',
        () {
      final accumulator = StreamingDecisionAccumulator();

      _consumeAll(accumulator, [
        const StreamingMessageStartEvent(messageId: 'm1'),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          blockType: StreamingContentBlockType.thinking,
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          deltaType: StreamingContentDeltaType.thinking,
          value: '先整理页面结构',
        ),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_invalid_1',
          toolName: 'write_file',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: '{"path":',
        ),
        const StreamingContentBlockStopEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
        ),
        const StreamingMessageStopEvent(messageId: 'm1'),
      ]);

      final decision = accumulator.buildDecision();
      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.visibleReasoning, '先整理页面结构');
      expect(decision.isTerminal, isTrue);
      expect(
        accumulator.debugSnapshot(),
        containsPair('assistantTextLength', 0),
      );
      final toolDrafts =
          accumulator.debugSnapshot()['toolDrafts'] as List<dynamic>;
      expect(toolDrafts, hasLength(1));
      expect(toolDrafts.first, containsPair('isCompleted', true));
      expect(toolDrafts.first, containsPair('rawArgumentsLength', 8));
    });

    test(
        'drops invalid create_artifact arguments with trailing garbage but preserves reasoning',
        () {
      final accumulator = StreamingDecisionAccumulator();

      _consumeAll(accumulator, [
        const StreamingMessageStartEvent(messageId: 'm1'),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          blockType: StreamingContentBlockType.thinking,
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          deltaType: StreamingContentDeltaType.thinking,
          value: '先整理页面结构。',
        ),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_artifact_bad_1',
          toolName: 'create_artifact',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value:
              '{"id":"china-food-ranking","type":"html","title":"中国美食排行","source":"<div>ok</div>"}',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: '\n<unexpected-tail>',
        ),
        const StreamingContentBlockStopEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
        ),
        const StreamingMessageStopEvent(messageId: 'm1'),
      ]);

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.visibleReasoning, '先整理页面结构。');
      expect(decision.isTerminal, isTrue);
      final toolDrafts =
          accumulator.debugSnapshot()['toolDrafts'] as List<dynamic>;
      expect(toolDrafts, hasLength(1));
      expect(toolDrafts.first, containsPair('isCompleted', true));
      expect(
        toolDrafts.first,
        containsPair('rawArgumentsLength', greaterThan(80)),
      );
    });

    test('finalizes chat-completions style tool call on stream completion', () {
      final accumulator = StreamingDecisionAccumulator();

      _consumeAll(accumulator, [
        const StreamingMessageStartEvent(messageId: 'm1'),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_search_1',
          toolName: 'search_chat_history',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: '{"query":"数据库版本"}',
        ),
        const StreamingMessageStopEvent(messageId: 'm1'),
      ]);

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.providerCallId, 'call_search_1');
      expect(decision.toolCalls.single.toolName, 'search_chat_history');
      expect(decision.toolCalls.single.arguments, {'query': '数据库版本'});
      expect(decision.isTerminal, isFalse);
    });

    test('keeps assistant text and reasoning when tool call streams too', () {
      final accumulator = StreamingDecisionAccumulator();

      _consumeAll(accumulator, [
        const StreamingMessageStartEvent(messageId: 'm1'),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          blockType: StreamingContentBlockType.thinking,
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          deltaType: StreamingContentDeltaType.thinking,
          value: '先确认上下文。',
        ),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          blockType: StreamingContentBlockType.text,
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '我先读取文件。',
        ),
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_read_1',
          toolName: 'read_file',
        ),
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: '{"path":"README.md"}',
        ),
        const StreamingContentBlockStopEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
        ),
        const StreamingMessageStopEvent(messageId: 'm1'),
      ]);

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.visibleReasoning, '先确认上下文。');
      expect(decision.assistantMessage, '我先读取文件。');
      expect(decision.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.providerCallId, 'call_read_1');
      expect(decision.toolCalls.single.toolName, 'read_file');
      expect(decision.toolCalls.single.arguments, {'path': 'README.md'});
      expect(decision.isTerminal, isFalse);
    });

    test('returns null when stream completes without any usable decision data',
        () {
      final accumulator = StreamingDecisionAccumulator();

      accumulator.consume(
        const StreamingMessageStopEvent(messageId: 'm1'),
      );

      expect(accumulator.buildDecision(), isNull);
    });
  });
}

void _consumeAll(
  StreamingDecisionAccumulator accumulator,
  List<StreamingMessageEvent> events,
) {
  for (final event in events) {
    accumulator.consume(event);
  }
}
