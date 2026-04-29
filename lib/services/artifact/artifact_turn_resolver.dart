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
    final artifactByPath = <String, _ArtifactIdentity>{};
    final occurrencesByArtifactId = <String, List<_ArtifactOccurrence>>{};
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

        artifactByPath[sourcePath] = _ArtifactIdentity(
          artifactId: artifactId,
          title: title,
          type: type,
          sourcePath: sourcePath,
        );
        _recordOccurrence(
          occurrencesByArtifactId,
          _ArtifactOccurrence(
            artifactId: artifactId,
            title: title,
            type: type,
            sourcePath: sourcePath,
            turnId: currentTurnId,
            sourceMessageId: message.id,
            timestamp: message.timestamp,
          ),
        );
        continue;
      }

      if (result.toolName != 'Write' && result.toolName != 'Edit') {
        continue;
      }

      final filePath = (result.data['filePath'] ?? '').toString().trim();
      final artifact = artifactByPath[filePath];
      if (artifact == null) {
        continue;
      }
      _recordOccurrence(
        occurrencesByArtifactId,
        _ArtifactOccurrence(
          artifactId: artifact.artifactId,
          title: artifact.title,
          type: artifact.type,
          sourcePath: artifact.sourcePath,
          turnId: currentTurnId,
          sourceMessageId: message.id,
          timestamp: message.timestamp,
        ),
      );
    }

    final projections = <ArtifactTurnProjection>[];
    for (final entry in occurrencesByArtifactId.entries) {
      final occurrences = [...entry.value]
        ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
      for (var index = 0; index < occurrences.length; index += 1) {
        final occurrence = occurrences[index];
        final isLatest = index == occurrences.length - 1;
        final source = isLatest
            ? _tryReadSource(occurrence.sourcePath)
            : null;
        projections.add(
          ArtifactTurnProjection(
            artifactId: occurrence.artifactId,
            turnId: occurrence.turnId,
            title: occurrence.title,
            type: occurrence.type,
            sourcePath: occurrence.sourcePath,
            source: source,
            isStale: !isLatest,
            sourceMessageId: occurrence.sourceMessageId,
            createdAt: occurrence.timestamp,
            updatedAt: occurrence.timestamp,
          ),
        );
      }
    }

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

  void _recordOccurrence(
    Map<String, List<_ArtifactOccurrence>> occurrencesByArtifactId,
    _ArtifactOccurrence occurrence,
  ) {
    final list =
        occurrencesByArtifactId.putIfAbsent(occurrence.artifactId, () => []);
    final existingIndex =
        list.indexWhere((item) => item.turnId == occurrence.turnId);
    if (existingIndex == -1) {
      list.add(occurrence);
      return;
    }
    if (list[existingIndex].timestamp.isBefore(occurrence.timestamp)) {
      list[existingIndex] = occurrence;
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

class _ArtifactIdentity {
  final String artifactId;
  final String title;
  final ArtifactType type;
  final String sourcePath;

  const _ArtifactIdentity({
    required this.artifactId,
    required this.title,
    required this.type,
    required this.sourcePath,
  });
}

class _ArtifactOccurrence {
  final String artifactId;
  final String title;
  final ArtifactType type;
  final String sourcePath;
  final String turnId;
  final int? sourceMessageId;
  final DateTime timestamp;

  const _ArtifactOccurrence({
    required this.artifactId,
    required this.title,
    required this.type,
    required this.sourcePath,
    required this.turnId,
    required this.sourceMessageId,
    required this.timestamp,
  });
}
