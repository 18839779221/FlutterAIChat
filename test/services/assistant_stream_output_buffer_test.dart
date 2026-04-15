import 'package:ai_chat/services/assistant_stream_output_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coalesces high-frequency deltas into fewer UI flushes', () async {
    final uiFlushes = <String>[];
    final persistedFlushes = <String>[];

    final buffer = AssistantStreamOutputBuffer(
      onUiFlush: uiFlushes.add,
      onPersistFlush: persistedFlushes.add,
      uiFlushInterval: const Duration(milliseconds: 20),
      persistFlushInterval: const Duration(milliseconds: 60),
    );
    addTearDown(buffer.dispose);

    buffer.onDelta('Hel');
    buffer.onDelta('lo');
    buffer.onDelta(' ');
    buffer.onDelta('world');

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(uiFlushes, isNotEmpty);
    expect(uiFlushes.last, 'Hello world');
    expect(uiFlushes.length, lessThan(4));
    expect(persistedFlushes, isEmpty);
  });

  test('flushes persistence less often and syncs final text on finish', () async {
    final uiFlushes = <String>[];
    final persistedFlushes = <String>[];

    final buffer = AssistantStreamOutputBuffer(
      onUiFlush: uiFlushes.add,
      onPersistFlush: persistedFlushes.add,
      uiFlushInterval: const Duration(milliseconds: 20),
      persistFlushInterval: const Duration(milliseconds: 80),
    );
    addTearDown(buffer.dispose);

    buffer.onDelta('Long');
    buffer.onDelta(' answer');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(uiFlushes.last, 'Long answer');
    expect(persistedFlushes, isEmpty);

    await buffer.finish();

    expect(persistedFlushes, isNotEmpty);
    expect(persistedFlushes.last, 'Long answer');
    expect(persistedFlushes.length, lessThanOrEqualTo(uiFlushes.length));
  });

  test('cancel preserves accumulated text before closing', () async {
    final uiFlushes = <String>[];
    final persistedFlushes = <String>[];

    final buffer = AssistantStreamOutputBuffer(
      onUiFlush: uiFlushes.add,
      onPersistFlush: persistedFlushes.add,
      uiFlushInterval: const Duration(milliseconds: 25),
      persistFlushInterval: const Duration(milliseconds: 100),
    );
    addTearDown(buffer.dispose);

    buffer.onDelta('partial');
    buffer.onDelta(' answer');

    await buffer.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(uiFlushes.last, 'partial answer');
    expect(persistedFlushes.last, 'partial answer');
  });
}
