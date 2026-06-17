import 'dart:async';

import 'package:ai_chat/bootstrap/app_bootstrap_scope.dart';
import 'package:ai_chat/bootstrap/bootstrap_startup_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bootstrap scope renders child while runtime is still loading',
      (tester) async {
    final runtimeCompleter = Completer<TestRuntime>();

    await tester.pumpWidget(
      AppBootstrapScope<TestRuntime>(
        initializeRuntime: () => runtimeCompleter.future,
        child: const _FakeApp(),
      ),
    );

    await tester.pump();

    expect(find.byType(_FakeApp), findsOneWidget);
    expect(find.text('shell ready'), findsOneWidget);
  });

  testWidgets('bootstrap scope emits first frame and ready startup anchors once',
      (tester) async {
    final runtimeCompleter = Completer<TestRuntime>();
    final events = <String>[];
    final probe = BootstrapStartupProbe(
      emit: ({required name, required elapsedMsSinceStart, Object? error}) {
        events.add(name);
      },
    )..mark('bootstrap.start');

    await tester.pumpWidget(
      AppBootstrapScope<TestRuntime>(
        initializeRuntime: () => runtimeCompleter.future,
        startupProbe: probe,
        child: const _FakeApp(),
      ),
    );

    await tester.pump();
    expect(events, isEmpty);

    runtimeCompleter.complete(const TestRuntime());
    await tester.pump();

    expect(events, contains('bootstrap.first_frame'));
    expect(
      events.where((event) => event == 'bootstrap.first_frame'),
      hasLength(1),
    );
    expect(events, contains('bootstrap.ready'));
    expect(events.where((event) => event == 'bootstrap.ready'), hasLength(1));
  });
}

class _FakeApp extends StatelessWidget {
  const _FakeApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('shell ready'),
        ),
      ),
    );
  }
}

class TestRuntime {
  const TestRuntime();
}
