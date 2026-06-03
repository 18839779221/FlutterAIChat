import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streaming cursor implementation and outdated spec guidance are retired', () {
    final repoRoot = Directory.current.path;
    final cursorFile = File(
      '$repoRoot/lib/widgets/animations/streaming_cursor.dart',
    );
    final motionSpec = File(
      '$repoRoot/docs/design/motion-design-system.md',
    ).readAsStringSync();
    final roadmap = File(
      '$repoRoot/docs/design/ui-ux-improvement-roadmap.md',
    ).readAsStringSync();

    expect(cursorFile.existsSync(), isFalse);
    expect(motionSpec.contains('StreamingCursor'), isFalse);
    expect(motionSpec.contains('缺少打字光标'), isFalse);
    expect(roadmap.contains('StreamingCursor'), isFalse);
    expect(roadmap.contains('缺少打字光标'), isFalse);
  });

  test('motion docs no longer prescribe stale implementation paths', () {
    final repoRoot = Directory.current.path;
    final motionSpec = File(
      '$repoRoot/docs/design/motion-design-system.md',
    ).readAsStringSync();
    final roadmap = File(
      '$repoRoot/docs/design/ui-ux-improvement-roadmap.md',
    ).readAsStringSync();

    for (final staleTerm in const [
      'AnimatedList',
      'ToolCompletionAnimation',
      'AnimatedTimelineEntry',
      'AnimatedTimelineRow',
      'BouncingScrollPhysics',
      'streaming_response_block.dart',
      'AnimatedElevation',
      'StaggeredList',
      'FadeSlideIn',
    ]) {
      expect(motionSpec.contains(staleTerm), isFalse, reason: staleTerm);
      expect(roadmap.contains(staleTerm), isFalse, reason: staleTerm);
    }
  });
}
