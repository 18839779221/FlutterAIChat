import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/settings/immersive_settings_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildHarness(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(430, 932),
          padding: EdgeInsets.only(top: 59, bottom: 34),
        ),
        child: child,
      ),
    );
  }

  testWidgets(
      'immersive settings scaffold renders fixed veil and floating header',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        const ImmersiveSettingsScaffold(
          title: '设置',
          body: SizedBox(height: 600, child: Text('body')),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('settings-top-overlay-veil')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-floating-header')),
      findsOneWidget,
    );
    expect(find.text('设置'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
  });

  testWidgets('immersive settings scaffold leaves substantial visible body area',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        ImmersiveSettingsScaffold(
          title: '设置',
          body: Container(
            key: const ValueKey('immersive-body-probe'),
            color: Colors.red,
            height: 600,
          ),
        ),
      ),
    );

    final bodyRect =
        tester.getRect(find.byKey(const ValueKey('immersive-body-probe')));

    expect(bodyRect.top, 125);
    expect(bodyRect.height, greaterThan(300));
  });

  testWidgets('immersive settings scaffold keeps top veil localized',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        const ImmersiveSettingsScaffold(
          title: '设置',
          body: SizedBox(height: 600, child: Text('body')),
        ),
      ),
    );

    final veilRect =
        tester.getRect(find.byKey(const ValueKey('settings-top-overlay-veil')));

    expect(veilRect.top, 0);
    expect(veilRect.height, lessThan(220));
  });

  testWidgets('immersive settings scaffold keeps floating header compact',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        const ImmersiveSettingsScaffold(
          title: '设置',
          body: SizedBox(height: 600, child: Text('body')),
        ),
      ),
    );

    final headerRect =
        tester.getRect(find.byKey(const ValueKey('settings-floating-header')));

    expect(headerRect.top, greaterThanOrEqualTo(59));
    expect(headerRect.height, 56);
  });

  testWidgets('immersive settings scaffold sets edge-to-edge status bar style',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        const ImmersiveSettingsScaffold(
          title: '设置',
          body: SizedBox(height: 600, child: Text('body')),
        ),
      ),
    );

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );

    expect(region.value.statusBarColor, Colors.transparent);
    expect(region.value.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('immersive settings scaffold uses extended top veil ramp',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        const ImmersiveSettingsScaffold(
          title: '设置',
          body: SizedBox(height: 600, child: Text('body')),
        ),
      ),
    );

    final veilRect =
        tester.getRect(find.byKey(const ValueKey('settings-top-overlay-veil')));

    expect(veilRect.height, greaterThan(140));
  });

  testWidgets('immersive settings scaffold root header avoids solid panel',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        const ImmersiveSettingsScaffold(
          title: '设置',
          body: SizedBox(height: 600, child: Text('body')),
        ),
      ),
    );

    expect(find.byKey(settingsFloatingHeaderSurfaceKey), findsNothing);
  });
}
