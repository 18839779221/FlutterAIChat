import 'package:ai_chat/models/artifact/artifact_type.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/services/artifact/runtime_artifact_preview_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeArtifactPreviewParser', () {
    const parser = RuntimeArtifactPreviewParser();

    test('parses partial create_artifact arguments into runtime preview', () {
      final preview = parser.parse(
        message: RuntimeStreamingPreviewMessage(
          messageId: 'message_1',
          createdAt: DateTime(2026, 5, 5, 10, 0, 0),
          updatedAt: DateTime(2026, 5, 5, 10, 0, 1),
          blocks: const [],
        ),
        block: RuntimeStreamingPreviewBlock(
          contentBlockId: 'message_1:tool:call_1',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_1',
          toolName: 'create_artifact',
          createdAt: DateTime(2026, 5, 5, 10, 0, 0),
          updatedAt: DateTime(2026, 5, 5, 10, 0, 1),
          text:
              '{"id":"sales-dashboard","type":"html","title":"Sales","source":"<style>body{margin:0}</style><div>Hello',
        ),
        turnId: '7_runtime',
      );

      expect(preview, isNotNull);
      expect(preview!.artifactId, 'sales-dashboard');
      expect(preview.title, 'Sales');
      expect(preview.type, ArtifactType.html);
      expect(preview.source, startsWith('<style>body{margin:0}</style>'));
    });

    test('ignores non artifact tool streams', () {
      final preview = parser.parse(
        message: RuntimeStreamingPreviewMessage(
          messageId: 'message_1',
          createdAt: DateTime(2026, 5, 5, 10, 0, 0),
          updatedAt: DateTime(2026, 5, 5, 10, 0, 1),
          blocks: const [],
        ),
        block: RuntimeStreamingPreviewBlock(
          contentBlockId: 'message_1:tool:call_1',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_1',
          toolName: 'Write',
          createdAt: DateTime(2026, 5, 5, 10, 0, 0),
          updatedAt: DateTime(2026, 5, 5, 10, 0, 1),
          text: '{"file_path":"a.txt"}',
        ),
        turnId: '7_runtime',
      );

      expect(preview, isNull);
    });
  });
}
