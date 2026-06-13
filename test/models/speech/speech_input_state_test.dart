import 'package:ai_chat/models/speech/speech_input_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracks active speech draft range for inline underline rendering', () {
    final state = const SpeechInputState().copyWith(
      draftText: '明天下午三点',
      draftRangeStart: 4,
      draftRangeEnd: 10,
    );

    expect(state.hasDraftRange, isTrue);
    expect(state.draftRangeStart, 4);
    expect(state.draftRangeEnd, 10);
  });
}
