import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:ai_chat/models/llm/streaming_planner_chunk.dart';
import 'package:ai_chat/models/chat/runtime_stream_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingDecisionAccumulator', () {
    test('aggregates terminal assistant text and reasoning', () {
      final accumulator = StreamingDecisionAccumulator();

      accumulator.consume(
        const StreamingPlannerChunk.reasoningDelta('先分析'),
      );
      accumulator.consume(
        const StreamingPlannerChunk.contentDelta('最终'),
      );
      accumulator.consume(
        const StreamingPlannerChunk.contentDelta('答案'),
      );
      accumulator.consume(
        const StreamingPlannerChunk.streamCompleted(),
      );

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, '最终答案');
      expect(decision.visibleReasoning, '先分析');
      expect(decision.isTerminal, isTrue);
    });

    test('preserves whitespace-only deltas inside assistant markdown', () {
      final accumulator = StreamingDecisionAccumulator();

      accumulator.consume(
        const StreamingPlannerChunk.contentDelta('# 标题'),
      );
      accumulator.consume(
        const StreamingPlannerChunk.contentDelta('\n\n'),
      );
      accumulator.consume(
        const StreamingPlannerChunk.contentDelta('```dart'),
      );
      accumulator.consume(
        const StreamingPlannerChunk.contentDelta('\n'),
      );
      accumulator.consume(
        const StreamingPlannerChunk.contentDelta('ListView.builder();'),
      );
      accumulator.consume(
        const StreamingPlannerChunk.streamCompleted(),
      );

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(
        decision!.assistantMessage,
        '# 标题\n\n```dart\nListView.builder();',
      );
    });

    test('aggregates completed tool call arguments by provider call id', () {
      final accumulator = StreamingDecisionAccumulator();

      accumulator.consume(
        const StreamingPlannerChunk.toolCallStarted(
          providerCallId: 'toolu_1',
          toolName: 'write_file',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.toolCallArgumentsDelta(
          providerCallId: 'toolu_1',
          argumentsTextDelta: '{"path":"a.txt",',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.toolCallArgumentsDelta(
          providerCallId: 'toolu_1',
          argumentsTextDelta: '"content":"hello"}',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.toolCallCompleted(
          providerCallId: 'toolu_1',
          toolName: 'write_file',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.streamCompleted(),
      );

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.providerCallId, 'toolu_1');
      expect(decision.toolCalls.single.toolName, 'write_file');
      expect(
        decision.toolCalls.single.arguments,
        {
          'path': 'a.txt',
          'content': 'hello',
        },
      );
      expect(decision.isTerminal, isFalse);
    });

    test('exposes runtime snapshot for streaming tool call arguments', () {
      final accumulator = StreamingDecisionAccumulator();

      accumulator.consume(
        const StreamingPlannerChunk.toolCallStarted(
          providerCallId: 'toolu_1',
          toolName: 'create_artifact',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.toolCallArgumentsDelta(
          providerCallId: 'toolu_1',
          toolName: 'create_artifact',
          argumentsTextDelta: '{"source":"<div>Hello',
        ),
      );

      final snapshots = accumulator.runtimeSnapshots(
        turnId: '7_runtime',
        now: DateTime(2026, 5, 5, 10),
      );

      expect(snapshots, hasLength(1));
      expect(snapshots.single.kind, RuntimeStreamEntryKind.toolCallArguments);
      expect(snapshots.single.providerCallId, 'toolu_1');
      expect(snapshots.single.toolName, 'create_artifact');
      expect(snapshots.single.text, contains('<div>Hello'));
    });

    test('keeps anonymous argument deltas attached to latest unfinished tool call',
        () {
      final accumulator = StreamingDecisionAccumulator();

      accumulator.consume(
        const StreamingPlannerChunk.toolCallStarted(
          providerCallId: 'call_1',
          toolName: 'create_artifact',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.toolCallArgumentsDelta(
          argumentsTextDelta: '{"id":"demo","type":"html","title":"Demo","source":"<div>Hello</div>"}',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.streamCompleted(),
      );

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.toolName, 'create_artifact');
      expect(
        decision.toolCalls.single.arguments['source'],
        '<div>Hello</div>',
      );
    });

    test('returns null when completed tool call arguments stay invalid', () {
      final accumulator = StreamingDecisionAccumulator();

      accumulator.consume(
        const StreamingPlannerChunk.toolCallStarted(
          providerCallId: 'toolu_1',
          toolName: 'write_file',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.toolCallArgumentsDelta(
          providerCallId: 'toolu_1',
          argumentsTextDelta: '{"path":',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.toolCallCompleted(
          providerCallId: 'toolu_1',
          toolName: 'write_file',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.streamCompleted(),
      );

      expect(accumulator.buildDecision(), isNull);
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

    test('finalizes chat-completions style tool call on stream completion', () {
      final accumulator = StreamingDecisionAccumulator();

      accumulator.consume(
        const StreamingPlannerChunk.toolCallStarted(
          providerCallId: 'call_1',
          toolName: 'search_chat_history',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.toolCallArgumentsDelta(
          providerCallId: 'call_1',
          argumentsTextDelta: '{"query":"数据库版本"}',
        ),
      );
      accumulator.consume(
        const StreamingPlannerChunk.streamCompleted(),
      );

      final decision = accumulator.buildDecision();

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.providerCallId, 'call_1');
      expect(decision.toolCalls.single.toolName, 'search_chat_history');
      expect(decision.toolCalls.single.arguments, {'query': '数据库版本'});
      expect(decision.isTerminal, isFalse);
    });

    test('returns null when stream completes without any usable decision data',
        () {
      final accumulator = StreamingDecisionAccumulator();

      accumulator.consume(
        const StreamingPlannerChunk.streamCompleted(),
      );

      expect(accumulator.buildDecision(), isNull);
    });
  });
}
