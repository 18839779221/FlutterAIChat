import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_timeline/stable_artifact_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'stable artifact block reuses cached subtree across unrelated parent rebuilds',
    (tester) async {
      var buildCount = 0;
      var tick = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Column(
                  children: [
                    Text('tick:$tick'),
                    StableArtifactBlock(
                      cacheKey: 'artifact-1',
                      builder: (_) {
                        buildCount++;
                        return const Text('artifact');
                      },
                    ),
                    TextButton(
                      onPressed: () => setState(() => tick++),
                      child: const Text('refresh'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(buildCount, 1);

      await tester.tap(find.text('refresh'));
      await tester.pump();

      expect(buildCount, 1);
    },
  );

  testWidgets(
    'stable artifact block rebuilds subtree after cache key changes',
    (tester) async {
      var buildCount = 0;
      var cacheKey = 'artifact-1';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Column(
                  children: [
                    StableArtifactBlock(
                      cacheKey: cacheKey,
                      builder: (_) {
                        buildCount++;
                        return Text(cacheKey);
                      },
                    ),
                    TextButton(
                      onPressed: () => setState(() => cacheKey = 'artifact-2'),
                      child: const Text('swap'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(buildCount, 1);
      expect(find.text('artifact-1'), findsOneWidget);

      await tester.tap(find.text('swap'));
      await tester.pump();

      expect(buildCount, 2);
      expect(find.text('artifact-2'), findsOneWidget);
    },
  );
}
