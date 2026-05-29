import 'dart:convert';

import 'package:ai_chat/models/artifact/artifact_type.dart';
import 'package:ai_chat/models/artifact/runtime_artifact_preview.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/utils/logger.dart';

/// Parses runtime-only artifact previews from raw streamed tool-call arguments.
class RuntimeArtifactPreviewParser {
  const RuntimeArtifactPreviewParser();

  RuntimeArtifactPreview? parse({
    required RuntimeStreamingPreviewMessage message,
    required RuntimeStreamingPreviewBlock block,
    required String turnId,
  }) {
    if (block.blockType != StreamingContentBlockType.toolUse) {
      return null;
    }
    if ((block.toolName ?? '').trim() != 'create_artifact') {
      return null;
    }

    Logger.temp(
      'RuntimeArtifactPreviewParser',
      'parsing create_artifact block',
      reason: 'diagnose streaming performance',
      data: {
        'textLength': block.text.length,
        'textPreview': block.text.length > 200
            ? '${block.text.substring(0, 200)}...'
            : block.text,
      },
    );

    final source = _extractJsonStringValue(block.text, 'source');
    final artifactId = _extractJsonStringValue(block.text, 'id')?.trim();
    final title = _extractJsonStringValue(block.text, 'title')?.trim();
    final typeName = _extractJsonStringValue(block.text, 'type')?.trim();
    final type = ArtifactTypeX.fromWireValue(typeName ?? 'html');

    // Return preview even if source is empty (streaming in progress)
    return RuntimeArtifactPreview(
      turnId: turnId,
      entryId: block.contentBlockId,
      artifactId:
          artifactId == null || artifactId.isEmpty ? 'runtime-artifact' : artifactId,
      title: title == null || title.isEmpty ? '正在生成 Artifact' : title,
      type: type,
      providerCallId: block.toolUseId?.trim(),
      source: source ?? '', // Allow empty source during streaming
      sourcePath:
          'runtime://create_artifact/${block.toolUseId ?? block.contentBlockId}',
      createdAt: block.createdAt,
      updatedAt: block.updatedAt,
    );
  }

  String? _extractJsonStringValue(String raw, String key) {
    final decoded = _tryDecodeCompleteJson(raw);
    if (decoded is Map<String, dynamic>) {
      final value = decoded[key];
      if (value is String) {
        return value;
      }
    }

    final keyIndex = raw.indexOf('"$key"');
    if (keyIndex == -1) {
      return null;
    }
    final colonIndex = raw.indexOf(':', keyIndex);
    if (colonIndex == -1) {
      return null;
    }
    var quoteIndex = colonIndex + 1;
    while (quoteIndex < raw.length &&
        (raw[quoteIndex] == ' ' ||
            raw[quoteIndex] == '\n' ||
            raw[quoteIndex] == '\r' ||
            raw[quoteIndex] == '\t')) {
      quoteIndex += 1;
    }
    if (quoteIndex >= raw.length || raw[quoteIndex] != '"') {
      return null;
    }

    final buffer = StringBuffer();
    var escaped = false;
    for (var index = quoteIndex + 1; index < raw.length; index += 1) {
      final char = raw[index];
      if (escaped) {
        switch (char) {
          case '"':
            buffer.write('"');
            break;
          case '\\':
            buffer.write(r'\');
            break;
          case '/':
            buffer.write('/');
            break;
          case 'b':
            buffer.write('\b');
            break;
          case 'f':
            buffer.write('\f');
            break;
          case 'n':
            buffer.write('\n');
            break;
          case 'r':
            buffer.write('\r');
            break;
          case 't':
            buffer.write('\t');
            break;
          case 'u':
            if (index + 4 >= raw.length) {
              return buffer.toString();
            }
            final hex = raw.substring(index + 1, index + 5);
            final codePoint = int.tryParse(hex, radix: 16);
            if (codePoint == null) {
              return buffer.toString();
            }
            buffer.write(String.fromCharCode(codePoint));
            index += 4;
            break;
          default:
            buffer.write(char);
            break;
        }
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        return buffer.toString();
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  Object? _tryDecodeCompleteJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
