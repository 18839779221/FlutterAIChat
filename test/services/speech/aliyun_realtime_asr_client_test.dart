import 'package:ai_chat/services/speech/aliyun_realtime_asr_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AliyunRealtimeAsrMessageParser', () {
    test('ignores task-started lifecycle event', () {
      final event = const AliyunRealtimeAsrMessageParser().parseMessage({
        'header': {
          'event': 'task-started',
        },
      });

      expect(event, isNull);
    });

    test('maps non-final result-generated payload into partial event', () {
      final event = const AliyunRealtimeAsrMessageParser().parseMessage({
        'header': {
          'event': 'result-generated',
        },
        'payload': {
          'output': {
            'sentence': {
              'text': '明天上午',
              'sentence_end': false,
            },
          },
        },
      });

      expect(event, isNotNull);
      expect(event!.type, AliyunAsrEventType.partial);
      expect(event.text, '明天上午');
    });

    test('maps final result-generated payload into final event', () {
      final event = const AliyunRealtimeAsrMessageParser().parseMessage({
        'header': {
          'event': 'result-generated',
        },
        'payload': {
          'output': {
            'sentence': {
              'text': '明天上午十点开会',
              'sentence_end': true,
            },
          },
        },
      });

      expect(event, isNotNull);
      expect(event!.type, AliyunAsrEventType.finalResult);
      expect(event.text, '明天上午十点开会');
    });

    test('ignores result-generated payload with blank text', () {
      final event = const AliyunRealtimeAsrMessageParser().parseMessage({
        'header': {
          'event': 'result-generated',
        },
        'payload': {
          'output': {
            'sentence': {
              'text': '   ',
              'sentence_end': false,
            },
          },
        },
      });

      expect(event, isNull);
    });
  });
}
