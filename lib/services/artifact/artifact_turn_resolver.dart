import '../../models/artifact/artifact_turn_projection.dart';
import '../../models/artifact/artifact_type.dart';
import '../../models/chat_message.dart';
import '../../models/response/message_content_type.dart';
import '../../models/tool/tool_result.dart';
import 'artifact_file_storage_service.dart';

class ArtifactTurnResolver {
  ArtifactTurnResolver({
    required ArtifactFileStorageService fileStorageService,
  }) : _fileStorageService = fileStorageService;

  final ArtifactFileStorageService _fileStorageService;

  List<ArtifactTurnProjection> resolve({
    required List<ChatMessage> messages,
    required int? groupId,
  }) {
    if (groupId == null || messages.isEmpty) {
      return const <ArtifactTurnProjection>[];
    }

    final sortedMessages = [...messages]..sort(compareChatMessagesForTimeline);
    final occurrences = <ArtifactTurnProjection>[];
    var currentTurnId = '';
    var fallbackUserIndex = 0;

    for (final message in sortedMessages) {
      if (message.isUser) {
        fallbackUserIndex += 1;
        currentTurnId = _buildTurnId(
          groupId: groupId,
          messageId: message.id,
          fallbackIndex: fallbackUserIndex,
        );
        continue;
      }

      currentTurnId = currentTurnId.isEmpty
          ? _buildTurnId(
              groupId: groupId,
              messageId: message.id,
              fallbackIndex: fallbackUserIndex + 1,
            )
          : currentTurnId;

      if (message.contentType != MessageContentType.toolResult) {
        continue;
      }

      final payload = message.payloadJson;
      if (payload == null) {
        continue;
      }
      final result = ToolResult.fromJson(payload);
      if (result.status != ToolExecutionStatus.success) {
        continue;
      }

      if (result.toolName == 'create_artifact') {
        final sourcePath = (result.data['sourcePath'] ?? '').toString().trim();
        final artifactId = (result.data['artifactId'] ?? '').toString().trim();
        final title = (result.data['title'] ?? artifactId).toString().trim();
        final type = ArtifactTypeX.fromWireValue(
          (result.data['type'] ?? 'html').toString(),
        );
        if (sourcePath.isEmpty || artifactId.isEmpty) {
          continue;
        }

        occurrences.add(
          ArtifactTurnProjection(
            artifactId: artifactId,
            turnId: currentTurnId,
            title: title,
            type: type,
            providerCallId: result.providerCallId,
            sourcePath: sourcePath,
            source: _tryReadSource(sourcePath),
            sourceMessageId: message.id,
            createdAt: message.timestamp,
            updatedAt: message.timestamp,
          ),
        );
      }
    }

    final projections = occurrences;
    projections.sort((left, right) {
      final turnOrder = left.createdAt.compareTo(right.createdAt);
      if (turnOrder != 0) {
        return turnOrder;
      }
      return left.artifactId.compareTo(right.artifactId);
    });
    return projections;
  }

  String? _tryReadSource(String sourcePath) {
    try {
      return _fileStorageService.readArtifactSourceSync(sourcePath);
    } catch (_) {
      return null;
    }
  }

  String _buildTurnId({
    required int? groupId,
    required int? messageId,
    required int fallbackIndex,
  }) {
    return '${groupId ?? 0}_${messageId ?? 'user_$fallbackIndex'}';
  }
}
