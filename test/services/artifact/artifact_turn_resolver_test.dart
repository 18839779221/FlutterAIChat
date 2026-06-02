import 'dart:io';

import 'package:ai_chat/models/artifact/artifact_type.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/services/artifact/artifact_file_storage_service.dart';
import 'package:ai_chat/services/artifact/artifact_turn_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactTurnResolver', () {
    test('keeps only create_artifact projections and ignores Write/Edit follow-up updates', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'artifact-resolver-',
      );
      final storage = ArtifactFileStorageService(rootDirectory: tempDirectory);
      await storage.saveArtifactSource(
        groupId: 7,
        artifactId: 'portfolio-pie',
        title: '投资组合饼图',
        type: ArtifactType.html,
        source: '<div>v2</div>',
      );
      final resolver = ArtifactTurnResolver(fileStorageService: storage);

      final messages = [
        ChatMessage(
          id: 1,
          text: '帮我做个图',
          role: MessageRole.user,
          timestamp: DateTime(2026, 4, 30, 10, 0, 0),
        ),
        ChatMessage(
          id: 2,
          text: '已创建 artifact',
          role: MessageRole.assistant,
          contentType: MessageContentType.toolResult,
          payloadJson: const {
            'toolName': 'create_artifact',
            'status': 'success',
            'summary': '已创建 artifact：portfolio-pie',
            'data': {
              'artifactId': 'portfolio-pie',
              'title': '投资组合饼图',
              'type': 'html',
              'sourcePath': '/artifacts/7/portfolio-pie.html',
            },
          },
          timestamp: DateTime(2026, 4, 30, 10, 0, 1),
        ),
        ChatMessage(
          id: 3,
          text: '已编辑文件',
          role: MessageRole.assistant,
          contentType: MessageContentType.toolResult,
          payloadJson: const {
            'toolName': 'Edit',
            'status': 'success',
            'summary': '已编辑文件：/artifacts/7/portfolio-pie.html',
            'data': {
              'filePath': '/artifacts/7/portfolio-pie.html',
            },
          },
          timestamp: DateTime(2026, 4, 30, 10, 0, 2),
        ),
        ChatMessage(
          id: 4,
          text: '换成环形图',
          role: MessageRole.user,
          timestamp: DateTime(2026, 4, 30, 10, 1, 0),
        ),
        ChatMessage(
          id: 5,
          text: '已编辑文件',
          role: MessageRole.assistant,
          contentType: MessageContentType.toolResult,
          payloadJson: const {
            'toolName': 'Write',
            'status': 'success',
            'summary': '已写入文件：/artifacts/7/portfolio-pie.html',
            'data': {
              'filePath': '/artifacts/7/portfolio-pie.html',
            },
          },
          timestamp: DateTime(2026, 4, 30, 10, 1, 1),
        ),
      ];

      final projections = resolver.resolve(messages: messages, groupId: 7);

      expect(projections, hasLength(1));
      expect(projections.first.turnId, '7_1');
      expect(projections.first.source, '<div>v2</div>');

      await tempDirectory.delete(recursive: true);
    });
  });
}
