import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatTraceRecorder', () {
    test('records events in insertion order for a single turn', () {
      final recorder = ChatTraceRecorder();
      final turnId = recorder.newTurnId();

      recorder.record(
        turnId: turnId,
        stage: ChatTraceStage.sendStart,
        status: ChatTraceStatus.started,
        summary: '发送开始',
      );
      recorder.record(
        turnId: turnId,
        stage: ChatTraceStage.sendDone,
        status: ChatTraceStatus.success,
        summary: '发送完成',
      );

      final events = recorder.eventsForTurn(turnId);

      expect(events, hasLength(2));
      expect(events[0].stage, ChatTraceStage.sendStart);
      expect(events[1].status, ChatTraceStatus.success);
    });

    test('keeps events from different turns isolated', () {
      final recorder = ChatTraceRecorder();
      final firstTurn = recorder.newTurnId();
      final secondTurn = recorder.newTurnId();

      recorder.record(
        turnId: firstTurn,
        stage: ChatTraceStage.sendStart,
        status: ChatTraceStatus.started,
      );
      recorder.record(
        turnId: secondTurn,
        stage: ChatTraceStage.sendDone,
        status: ChatTraceStatus.failure,
      );

      expect(recorder.eventsForTurn(firstTurn), hasLength(1));
      expect(recorder.eventsForTurn(secondTurn), hasLength(1));
      expect(
        recorder.eventsForTurn(secondTurn).first.stage,
        ChatTraceStage.sendDone,
      );
    });

    test('structured log includes metadata fields', () {
      final recordedEntries = <Map<String, dynamic>>[];
      final recorder = ChatTraceRecorder(
        logger: (entry) => recordedEntries.add(entry),
      );
      final turnId = recorder.newTurnId();

      recorder.record(
        turnId: turnId,
        stage: ChatTraceStage.sendStart,
        status: ChatTraceStatus.started,
        summary: 'sending payload',
      );

      final log = recordedEntries.single;

      expect(log['turnId'], turnId);
      expect(log['stage'], ChatTraceStage.sendStart.name);
      expect(log['status'], ChatTraceStatus.started.name);
      expect(log['summary'], 'sending payload');
      expect(log, contains('timestamp'));
    });

    test('automatically redacts sensitive data', () {
      final recordedEntries = <Map<String, dynamic>>[];
      final recorder = ChatTraceRecorder(
        logger: (entry) => recordedEntries.add(entry),
      );
      final turnId = recorder.newTurnId();

      recorder.record(
        turnId: turnId,
        stage: ChatTraceStage.sendStart,
        status: ChatTraceStatus.started,
        data: {
          'apiKey': 'secret',
          'authorization': 'Bearer token',
          'api_key': 'another secret',
          'nested': {
            'apiKey': 'also secret',
          },
          'normal': 'value',
        },
      );

      final sanitizedData = recordedEntries.single['data'] as Map<String, dynamic>;

      expect(sanitizedData['apiKey'], 'REDACTED');
      expect(sanitizedData['authorization'], 'REDACTED');
      expect(sanitizedData['api_key'], 'REDACTED');
      expect((sanitizedData['nested'] as Map)['apiKey'], 'REDACTED');
      expect(sanitizedData['normal'], 'value');
    });

    test('formats trace logs into preview-safe single line output', () {
      final recorder = ChatTraceRecorder();

      final formatted = recorder.formatLogLine({
        'turnId': 'turn-1',
        'stage': ChatTraceStage.llmRequestStart.name,
        'status': ChatTraceStatus.started.name,
        'summary': '开始请求',
        'data': {
          'apiKey': 'secret',
          'userMessagePreview': '这是一段非常长的预览文本' * 20,
          'toolName': 'web_search',
        },
      });

      expect(formatted, contains('turnId=turn-1'));
      expect(formatted, contains('stage=llmRequestStart'));
      expect(formatted, contains('status=started'));
      expect(formatted, contains('summary=开始请求'));
      expect(formatted, contains('toolName=web_search'));
      expect(formatted, contains('apiKey=REDACTED'));
      expect(formatted, isNot(contains('secret')));
      expect(formatted.length, lessThan(320));
    });
  });
}
