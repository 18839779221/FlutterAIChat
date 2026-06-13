import 'package:ai_chat/controllers/composer_text_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('underlines only the active speech draft range', (tester) async {
    final controller = ComposerTextEditingController()
      ..text = '帮我安排一下明天下午三点开会';
    controller.updateSpeechDraftRange(start: 6, end: 12);

    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(fontSize: 14),
              withComposing: false,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(span.children, hasLength(3));
    final underlinedSpan = span.children![1] as TextSpan;
    expect(underlinedSpan.text, '明天下午三点');
    expect(
      underlinedSpan.style?.decoration,
      TextDecoration.underline,
    );
  });
}
