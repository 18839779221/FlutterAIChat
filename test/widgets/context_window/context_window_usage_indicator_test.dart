import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/context_window/context_window_usage_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ContextWindowSnapshot _snapshot(double ratio) {
  return ContextWindowSnapshot(
    modelName: 'gpt-test',
    maxContextTokens: 128000,
    effectiveInputBudget: 104000,
    autoCompactTriggerTokens: 91000,
    totalEstimatedInputTokens: 1000,
    plannerInputUsageRatio: ratio,
    totalWindowUsageRatio: 0.0,
    effectiveInputUsageRatio: 0.0,
    didCompactHistory: false,
    recentCompletedTurnCount: 0,
    segments: const <ContextWindowSegment>[],
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      extensions: <ThemeExtension<dynamic>>[
        AppThemeSpec.light(),
        AppSpacing.base(),
        AppRadius.base(),
      ],
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('renders ring with visible percentage text', (tester) async {
    await tester.pumpWidget(
      _host(
        ContextWindowUsageIndicator(
          snapshot: _snapshot(0.23),
          onTap: () {},
        ),
      ),
    );

    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.23, 1e-9));
    expect(ring.strokeWidth, 2.0);
    expect(find.text('23%'), findsOneWidget);

    final ringSize = tester.getSize(find.byType(CircularProgressIndicator));
    expect(ringSize.width, 16);
    expect(ringSize.height, 16);
  });

  testWidgets('tap hit area is at least 32x32 and invokes onTap once', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        ContextWindowUsageIndicator(
          snapshot: _snapshot(0.5),
          onTap: () => taps += 1,
        ),
      ),
    );

    final hitSize = tester.getSize(
      find.byKey(const ValueKey('context-window-usage-indicator')),
    );
    expect(hitSize.width, greaterThanOrEqualTo(32));
    expect(hitSize.height, greaterThanOrEqualTo(32));

    await tester.tap(find.byKey(const ValueKey('context-window-usage-indicator')));
    expect(taps, 1);
  });

  testWidgets('semantics label includes rounded percentage', (tester) async {
    await tester.pumpWidget(
      _host(
        ContextWindowUsageIndicator(
          snapshot: _snapshot(0.236),
          onTap: () {},
        ),
      ),
    );

    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Planner 输入使用率 24%'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('color shifts to warning at or above planner trigger ratio', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ContextWindowUsageIndicator(
          snapshot: _snapshot(1.0),
          onTap: () {},
        ),
      ),
    );

    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    final expected = AppThemeSpec.light().workflowWarning.withValues(alpha: 0.72);
    expect(
      (ring.valueColor as AlwaysStoppedAnimation<Color>).value.toARGB32(),
      expected.toARGB32(),
    );
  });
}
