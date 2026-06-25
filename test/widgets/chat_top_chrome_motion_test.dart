import 'package:ai_chat/widgets/chat_top_chrome_motion.dart';
import 'package:ai_chat/widgets/chat_top_bar_button.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatTopChromeMotion', () {
    test('maps scroll offset into a clamped gather progress', () {
      final motion = ChatTopChromeMotion.fromScrollOffset(
        offset: 18,
        transitionDistance: 36,
      );

      expect(motion.chromeGatherProgress, 0.5);
      expect(motion.groupInsetProgress, greaterThan(0));
      expect(motion.groupInsetProgress, lessThan(1));
    });

    test('clamps the gather progress to relaxed and gathered bounds', () {
      final relaxed = ChatTopChromeMotion.fromScrollOffset(
        offset: -12,
        transitionDistance: 36,
      );
      final gathered = ChatTopChromeMotion.fromScrollOffset(
        offset: 80,
        transitionDistance: 36,
      );

      expect(relaxed.chromeGatherProgress, 0);
      expect(relaxed.groupInsetProgress, 0);
      expect(relaxed.materialFocusProgress, 0);
      expect(relaxed.shadowTightenProgress, 0);
      expect(relaxed.centerSettleProgress, 0);

      expect(gathered.chromeGatherProgress, 1);
      expect(gathered.groupInsetProgress, 1);
      expect(gathered.materialFocusProgress, 1);
      expect(gathered.shadowTightenProgress, 1);
      expect(gathered.centerSettleProgress, 1);
    });

    test('center settle progress lags behind group inset progress', () {
      final motion = ChatTopChromeMotion.fromProgress(0.72);

      expect(motion.centerSettleProgress, lessThan(motion.groupInsetProgress));
      expect(motion.shadowTightenProgress, lessThanOrEqualTo(1));
      expect(motion.shadowTightenProgress, greaterThan(0));
    });

    test('derived progresses stay monotonic as the chrome gathers', () {
      final early = ChatTopChromeMotion.fromProgress(0.2);
      final middle = ChatTopChromeMotion.fromProgress(0.5);
      final late = ChatTopChromeMotion.fromProgress(0.85);

      expect(early.groupInsetProgress, lessThan(middle.groupInsetProgress));
      expect(middle.groupInsetProgress, lessThan(late.groupInsetProgress));

      expect(
        early.materialFocusProgress,
        lessThan(middle.materialFocusProgress),
      );
      expect(
        middle.materialFocusProgress,
        lessThan(late.materialFocusProgress),
      );

      expect(
        early.centerSettleProgress,
        lessThan(middle.centerSettleProgress),
      );
      expect(
        middle.centerSettleProgress,
        lessThan(late.centerSettleProgress),
      );
    });

    testWidgets(
        'icon-only top bar button remains circular across motion states',
        (tester) async {
      const shellKey = ValueKey('motion-shell');

      Future<void> pumpForMotion(ChatTopChromeMotion motion) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: ChatTopBarButton(
                  shellKey: shellKey,
                  tooltip: 'Menu',
                  icon: Icons.menu,
                  onPressed: () {},
                  motion: motion,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pumpForMotion(ChatTopChromeMotion.fromProgress(0));
      final relaxedSize = tester.getSize(find.byKey(shellKey));

      await pumpForMotion(ChatTopChromeMotion.fromProgress(1));
      final gatheredSize = tester.getSize(find.byKey(shellKey));

      expect(relaxedSize.width, relaxedSize.height);
      expect(gatheredSize.width, gatheredSize.height);
    });
  });
}
