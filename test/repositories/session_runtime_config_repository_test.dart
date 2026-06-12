import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/session/session_runtime_config.dart';
import 'package:ai_chat/repositories/session_runtime_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SessionRuntimeConfigRepository', () {
    test('upserts and reloads runtime config by group', () async {
      final storage = DatabaseHelper(
        databaseName: 'session_runtime_config_repository_test.db',
      );
      final repository = SessionRuntimeConfigRepository(storage);
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Runtime Session'),
      );

      await repository.upsert(
        SessionRuntimeConfig(
          groupId: groupId,
          providerId: 'openai',
          modelId: 'gpt-5.4',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          sideProviderId: 'anthropic',
          sideModelId: 'claude-haiku',
          sideProviderStyle: ChatTurnProviderStyle.anthropicMessages,
        ),
      );

      final created = await repository.getByGroup(groupId);
      expect(created, isNotNull);
      expect(created!.providerId, 'openai');
      expect(created.modelId, 'gpt-5.4');
      expect(created.providerStyle, ChatTurnProviderStyle.openaiResponses);
      expect(created.sideProviderId, 'anthropic');
      expect(created.sideModelId, 'claude-haiku');
      expect(created.sideProviderStyle, ChatTurnProviderStyle.anthropicMessages);

      await repository.upsert(
        created.copyWith(
          providerId: 'anthropic',
          modelId: 'claude-sonnet-4-5',
          providerStyle: ChatTurnProviderStyle.anthropicMessages,
          clearSideProviderId: true,
          clearSideModelId: true,
          clearSideProviderStyle: true,
        ),
      );

      final updated = await repository.getByGroup(groupId);
      expect(updated, isNotNull);
      expect(updated!.providerId, 'anthropic');
      expect(updated.modelId, 'claude-sonnet-4-5');
      expect(updated.providerStyle, ChatTurnProviderStyle.anthropicMessages);
      expect(updated.sideProviderId, isNull);
      expect(updated.sideModelId, isNull);
      expect(updated.sideProviderStyle, isNull);

      await storage.deleteGroup(groupId);
    });
  });
}
