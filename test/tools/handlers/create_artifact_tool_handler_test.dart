import 'dart:io';

import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/repositories/artifact_repository.dart';
import 'package:ai_chat/services/artifact/artifact_file_storage_service.dart';
import 'package:ai_chat/services/artifact/artifact_source_sanitizer.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/create_artifact_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CreateArtifactToolHandler', () {
    test('prompt enforces host-root authoring scope and preflight checklist', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'create-artifact-prompt-',
      );
      final ChatStorage storage = DatabaseHelper(
        databaseName: 'create_artifact_prompt_test_v12.db',
      );
      final handler = CreateArtifactToolHandler(
        artifactRepository: ArtifactRepository(storage),
        fileStorageService:
            ArtifactFileStorageService(rootDirectory: tempDirectory),
        sanitizer: const ArtifactSourceSanitizer(),
      );

      expect(
        handler.definition.descriptionForModel,
        contains('always rendered inside the host-provided `#artifact-root`'),
      );
      expect(
        handler.definition.descriptionForModel,
        contains('Before writing `source`, verify all of the following:'),
      );
      expect(
        handler.definition.descriptionForModel,
        contains(
          'Treat the latest guideline result as the required authoring contract',
        ),
      );
      expect(
        handler.definition.descriptionForModel,
        contains('one screen'),
      );
      expect(
        handler.definition.descriptionForModel,
        contains('two screens'),
      );
      expect(
        handler.definition.descriptionForModel,
        contains('Do not generate a full page document structure'),
      );
      expect(
        handler.definition.descriptionForModel,
        contains('Do not make `html` or `body` the primary authored surface'),
      );
      expect(
        handler.definition.descriptionForModel,
        contains('I am not declaring a replacement root theme token set'),
      );
      expect(
        handler.definition.descriptionForModel,
        isNot(contains('three screens')),
      );
      expect(
        handler.definition.descriptionForModel,
        isNot(contains('prefer using Read/Edit/Write')),
      );
      expect(
        handler.definition.descriptionForModel,
        isNot(contains('incomplete intermediate HTML')),
      );
      expect(
        handler.definition.descriptionForModel,
        isNot(contains('degrade gracefully while the source is streaming in')),
      );
      expect(
        handler.definition.descriptionForModel,
        isNot(contains('Edit/Write operations on the same sourcePath')),
      );
      expect(
        handler.definition.descriptionForModel,
        isNot(contains('#3B82F6')),
      );
      expect(
        handler.definition.descriptionForModel,
        isNot(contains('0 1px 3px rgba(0,0,0,0.08)')),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        contains('`#artifact-root`'),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        contains('在编写 `source` 前'),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        contains('强制 authoring contract'),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        contains('1 屏内'),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        contains('2 屏'),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        contains('不要生成完整页面文档结构'),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        contains('我没有声明替代性的根级主题 token 集'),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        isNot(contains('3 屏')),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        isNot(contains('优先对返回的 sourcePath 使用 Read/Edit/Write')),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        isNot(contains('后续可能通过同一 sourcePath 上的 Edit/Write 重新渲染')),
      );
      expect(
        handler.definition.localizedDescriptionForModel?.chinese,
        isNot(contains('#3B82F6')),
      );

      await tempDirectory.delete(recursive: true);
    });

    test('stores source and returns editable sourcePath', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'create-artifact-handler-',
      );
      final ChatStorage storage = DatabaseHelper(
        databaseName: 'create_artifact_handler_test_v12.db',
      );
      final groupId =
          await storage.insertGroup(ChatGroup(title: 'artifact handler group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      final repository = ArtifactRepository(storage);
      final handler = CreateArtifactToolHandler(
        artifactRepository: repository,
        fileStorageService:
            ArtifactFileStorageService(rootDirectory: tempDirectory),
        sanitizer: const ArtifactSourceSanitizer(),
      );

      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'id': 'portfolio-pie',
          'type': 'html',
          'title': '投资组合饼图',
          'source': '<div>hello</div>',
        },
        userMessage: 'create artifact',
        history: const <ChatMessage>[],
        now: DateTime(2026, 4, 30, 10),
      );

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: groupId,
          toolName: 'create_artifact',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 30, 10),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['sourcePath'], 'artifacts/$groupId/portfolio-pie.html');
      expect(result.summary, contains('portfolio-pie'));
      expect(result.data['message'], contains('sourcePath'));

      final record = await repository.findByGroupAndArtifactId(
        groupId: groupId,
        artifactId: 'portfolio-pie',
      );
      expect(record, isNotNull);

      await storage.deleteGroup(groupId);
      await tempDirectory.delete(recursive: true);
    });
  });
}
