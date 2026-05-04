import 'package:ai_chat/models/artifact/artifact_type.dart';
import 'package:ai_chat/models/chat/runtime_stream_entry.dart';
import 'package:ai_chat/services/artifact/runtime_artifact_preview_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeArtifactPreviewParser', () {
    const parser = RuntimeArtifactPreviewParser();

    test('parses partial create_artifact arguments into runtime preview', () {
      final preview = parser.parse(
        RuntimeStreamEntry(
          turnId: '7_runtime',
          entryId: '7_runtime-tool-1',
          kind: RuntimeStreamEntryKind.toolCallArguments,
          providerCallId: 'call_1',
          toolName: 'create_artifact',
          createdAt: DateTime(2026, 5, 5, 10, 0, 0),
          updatedAt: DateTime(2026, 5, 5, 10, 0, 1),
          text:
              '{"id":"sales-dashboard","type":"html","title":"Sales","source":"<style>body{margin:0}</style><div>Hello',
        ),
      );

      expect(preview, isNotNull);
      expect(preview!.artifactId, 'sales-dashboard');
      expect(preview.title, 'Sales');
      expect(preview.type, ArtifactType.html);
      expect(preview.source, startsWith('<style>body{margin:0}</style>'));
    });

    test('ignores non artifact tool streams', () {
      final preview = parser.parse(
        RuntimeStreamEntry(
          turnId: '7_runtime',
          entryId: '7_runtime-tool-1',
          kind: RuntimeStreamEntryKind.toolCallArguments,
          providerCallId: 'call_1',
          toolName: 'Write',
          createdAt: DateTime(2026, 5, 5, 10, 0, 0),
          updatedAt: DateTime(2026, 5, 5, 10, 0, 1),
          text: '{"file_path":"a.txt"}',
        ),
      );

      expect(preview, isNull);
    });
  });
}
