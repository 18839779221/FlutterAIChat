import 'dart:async';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/chat/send_message_request.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/session/session_runtime_config.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/skill/skill_descriptor.dart';
import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_timeline_projection_service.dart';
import 'package:ai_chat/services/session_runtime_config_service.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/services/turn_verifier.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/transcript_builder_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DefaultChatSendCoordinator', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test(
        'preview-driven streaming response avoids persisted generating assistant message',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final afterEventsGate = Completer<void>();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '你好，',
          ),
        ],
        afterEventsGate: afterEventsGate,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      final previewNotifier =
          container.read(runtimeStreamingPreviewStateProvider.notifier);
      previewNotifier.publish(
        const StreamingMessageStartEvent(messageId: 'preview_1'),
      );
      previewNotifier.publish(
        const StreamingContentBlockStartEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          blockType: StreamingContentBlockType.text,
        ),
      );
      previewNotifier.publish(
        const StreamingContentBlockDeltaEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '你好，',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));

      final sendFuture = container.read(chatSendCoordinatorProvider).sendMessage(
            '打一声招呼',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      await _waitForSendPhase(container, ChatSendPhase.streamingResponse);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        container
            .read(messagesProvider)
            .where((message) => message.role == MessageRole.assistant),
        isEmpty,
      );
      expect(container.read(runtimeAssistantDraftProvider), isNull);

      afterEventsGate.complete();
      await sendFuture.timeout(const Duration(seconds: 1));
    });

    test('completes a streamed assistant reply on final answer', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '你好，',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '世界',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '你好，世界',
          ),
        ],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '打一声招呼',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final assistant = container
          .read(messagesProvider)
          .lastWhere((message) => message.role == MessageRole.assistant);
      expect(assistant.text, '你好，世界');
      expect(assistant.status, MessageStatus.completed);
      expect(container.read(chatSendStateProvider).phase, ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);

      final persisted = await databaseHelper.getMessagesByGroup(groupId);
      final persistedAssistant = persisted
          .lastWhere((message) => message.role == MessageRole.assistant);
      expect(persistedAssistant.text, '你好，世界');
      expect(persistedAssistant.status, MessageStatus.completed);
    });

    test('persists image attachments on the user message before agent loop',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      await container.read(chatSendCoordinatorProvider).sendMessageRequest(
            SendMessageRequest(
              text: '分析这张图',
              attachments: [
                ChatAttachment.image(
                  localId: 'att-1',
                  fileName: 'demo.png',
                  mimeType: 'image/png',
                  byteSize: 128,
                  localPath: '/tmp/demo.png',
                  status: ChatAttachmentStatus.ready,
                ),
              ],
            ),
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      final persisted = await databaseHelper.getMessagesByGroup(groupId);
      final userMessage = persisted.singleWhere((message) => message.isUser);
      expect(userMessage.attachments, hasLength(1));
      expect(userMessage.attachments.single.fileName, 'demo.png');
    });

    test('persists trace turn id into runtime context before agent loop',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      await container.read(chatSendCoordinatorProvider).sendMessage(
            'trace this turn',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      expect(harness.recordedTurns, isNotEmpty);
      final runtimeContext =
          harness.recordedTurns.single.providerStateJson?['runtime_context']
              as Map<String, dynamic>?;
      final traceTurnId = runtimeContext?['trace_turn_id'] as String?;
      expect(traceTurnId, isNotNull);
      expect(traceTurnId, isNotEmpty);
      expect(traceTurnId, startsWith('turn_'));
    });

    test('keeps attachment-only send out of persisted user text messages',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      await container.read(chatSendCoordinatorProvider).sendMessageRequest(
            SendMessageRequest(
              text: '',
              attachments: [
                ChatAttachment.image(
                  localId: 'att-1',
                  fileName: 'demo.png',
                  mimeType: 'image/png',
                  byteSize: 128,
                  localPath: '/tmp/demo.png',
                  status: ChatAttachmentStatus.ready,
                ),
              ],
            ),
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      final inMemoryUserMessages = container
          .read(messagesProvider)
          .where((message) => message.isUser)
          .toList();
      expect(inMemoryUserMessages, hasLength(1));
      expect(inMemoryUserMessages.single.text, isEmpty);
      expect(inMemoryUserMessages.single.attachments, hasLength(1));

      final persisted = await databaseHelper.getMessagesByGroup(groupId);
      expect(persisted.where((message) => message.isUser), isEmpty);
    });

    test('creates a draft current group when send starts without one',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      expect(container.read(currentGroupProvider), isNull);

      await container.read(chatSendCoordinatorProvider).sendMessageRequest(
            SendMessageRequest(
              text: '分析这张图',
              attachments: [
                ChatAttachment.image(
                  localId: 'att-1',
                  fileName: 'demo.png',
                  mimeType: 'image/png',
                  byteSize: 128,
                  localPath: '/tmp/demo.png',
                  status: ChatAttachmentStatus.ready,
                ),
              ],
            ),
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      expect(container.read(currentGroupProvider), isNotNull);
      final allMessages = container.read(messagesProvider);
      expect(allMessages.where((message) => message.role == MessageRole.user), hasLength(1));
    });

    test('persists current draft session runtime config when first send creates the group',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      container.read(currentSessionRuntimeConfigProvider.notifier).state =
          SessionRuntimeConfig(
        groupId: SessionRuntimeConfigService.draftGroupId,
        providerId: 'anthropic',
        modelId: 'claude-sonnet-4-5',
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
      );

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '打一声招呼',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      final currentGroup = container.read(currentGroupProvider);
      expect(currentGroup?.id, isNotNull);

      final runtimeConfig = await databaseHelper.getSessionRuntimeConfigByGroup(
        currentGroup!.id!,
      );
      expect(runtimeConfig, isNotNull);
      expect(runtimeConfig!.providerId, 'anthropic');
      expect(runtimeConfig.modelId, 'claude-sonnet-4-5');
      expect(runtimeConfig.providerStyle, ChatTurnProviderStyle.anthropicMessages);
    });

    test('passes current session runtime override into turn config', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
      );
      final settingsRepository = await _createSettingsRepository(
        defaultProviderId: 'global-provider',
        defaultModelId: 'global-model',
        providers: [
          LlmProviderConfig(
            id: 'global-provider',
            name: 'Global',
            apiKey: 'global-key',
            baseUrl: 'https://global.example/v1/chat/completions',
            apiStyle: ApiStyle.chatCompletions,
            models: const [
              LlmProviderModel(
                id: 'global-model',
                name: 'global-model',
              ),
            ],
          ),
          LlmProviderConfig(
            id: 'session-provider',
            name: 'Session',
            apiKey: 'session-key',
            baseUrl: 'https://session.example/v1/chat/completions',
            apiStyle: ApiStyle.chatCompletions,
            models: const [
              LlmProviderModel(
                id: 'session-model',
                name: 'session-model',
              ),
            ],
          ),
        ],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
        settingsRepository: settingsRepository,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      container.read(currentSessionRuntimeConfigProvider.notifier).state =
          SessionRuntimeConfig(
        groupId: groupId,
        providerId: 'session-provider',
        modelId: 'session-model',
        providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
      );

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '使用当前会话模型',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      expect(harness.recordedConfigs, hasLength(1));
      final runtimeOverride =
          harness.recordedConfigs.single.runtimeConfigOverride;
      expect(runtimeOverride, isNotNull);
      expect(runtimeOverride?.apiKey, 'session-key');
      expect(runtimeOverride?.apiUrl, 'https://session.example/v1/chat/completions');
      expect(runtimeOverride?.model, 'session-model');
      expect(runtimeOverride?.apiStyle, ApiStyle.chatCompletions);
    });

    test('persists current session provider style onto created turn', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
      );
      final settingsRepository = await _createSettingsRepository(
        defaultProviderId: 'responses-provider',
        defaultModelId: 'responses-model',
        providers: [
          LlmProviderConfig(
            id: 'responses-provider',
            name: 'Responses',
            apiKey: 'responses-key',
            baseUrl: 'https://responses.example/v1/responses',
            apiStyle: ApiStyle.responses,
            models: const [
              LlmProviderModel(
                id: 'responses-model',
                name: 'responses-model',
              ),
            ],
          ),
        ],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
        settingsRepository: settingsRepository,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      container.read(currentSessionRuntimeConfigProvider.notifier).state =
          SessionRuntimeConfig(
        groupId: groupId,
        providerId: 'responses-provider',
        modelId: 'responses-model',
        providerStyle: ChatTurnProviderStyle.openaiResponses,
      );

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '继续当前响应风格',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      expect(harness.recordedTurns, hasLength(1));
      expect(
        harness.recordedTurns.single.providerStyle,
        ChatTurnProviderStyle.openaiResponses,
      );
      expect(harness.recordedTurns.single.modelName, 'responses-model');
    });

    test(
        'allows image attachments to continue when request explicitly overrides unsupported image guard',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
        llm: _ImageUnsupportedBaseLLM(),
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      await container.read(chatSendCoordinatorProvider).sendMessageRequest(
            SendMessageRequest(
              text: '分析这张图',
              allowUnsupportedImageInputAttempt: true,
              attachments: [
                ChatAttachment.image(
                  localId: 'att-1',
                  fileName: 'demo.png',
                  mimeType: 'image/png',
                  byteSize: 128,
                  localPath: '/tmp/demo.png',
                  status: ChatAttachmentStatus.ready,
                ),
              ],
            ),
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      final allMessages = await databaseHelper.getMessagesByGroup(groupId);
      expect(
        allMessages.where((message) => message.role == MessageRole.user),
        hasLength(1),
      );
      expect(container.read(chatSendStateProvider).phase, ChatSendPhase.idle);
    });

    test(
        'prefers runtime capability override over static unsupported model flag',
        () async {
      SharedPreferences.setMockInitialValues({});
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
      );
      final settingsRepository = AppSettingsRepository(
        await SharedPreferences.getInstance(),
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'chat',
          defaultModelId: 'text-only-model',
          providers: [
            LlmProviderConfig(
              id: 'chat',
              name: 'Chat Provider',
              apiKey: 'key',
              baseUrl: 'https://example.com/v1/chat/completions',
              models: [
                LlmProviderModel(
                  id: 'text-only-model',
                  name: 'Text Only Model',
                  supportsImageInput: false,
                ),
              ],
            ),
          ],
        ),
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
        settingsRepository: settingsRepository,
      );
      addTearDown(container.dispose);
      await settingsRepository.saveRuntimeImageInputSupport(
        providerId: 'chat',
        modelId: 'text-only-model',
        supportsImageInput: true,
      );

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      await container.read(chatSendCoordinatorProvider).sendMessageRequest(
            SendMessageRequest(
              text: '分析这张图',
              attachments: [
                ChatAttachment.image(
                  localId: 'att-1',
                  fileName: 'demo.png',
                  mimeType: 'image/png',
                  byteSize: 128,
                  localPath: '/tmp/demo.png',
                  status: ChatAttachmentStatus.ready,
                ),
              ],
            ),
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      expect(harness.recordedTurns, isNotEmpty);
      final runtimeContext =
          harness.recordedTurns.single.providerStateJson?['runtime_context']
              as Map<String, dynamic>?;
      final rawAttachments = runtimeContext?['user_attachments'] as List?;
      expect(rawAttachments, isNotNull);
      expect(rawAttachments, hasLength(1));
      expect(rawAttachments!.single['localId'], 'att-1');
    });

    test(
        'preview-driven streamed reply settles as one completed assistant message',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '你好，',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '世界',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '你好，世界',
            payloadJson: const {
              'previewMessageId': 'preview_1',
            },
          ),
        ],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      final previewNotifier =
          container.read(runtimeStreamingPreviewStateProvider.notifier);
      previewNotifier.publish(
        const StreamingMessageStartEvent(messageId: 'preview_1'),
      );
      previewNotifier.publish(
        const StreamingContentBlockStartEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          blockType: StreamingContentBlockType.text,
        ),
      );
      previewNotifier.publish(
        const StreamingContentBlockDeltaEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '你好，世界',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '打一声招呼',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final assistantMessages = container
          .read(messagesProvider)
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages, hasLength(1));
      expect(assistantMessages.single.text, '你好，世界');
      expect(assistantMessages.single.status, MessageStatus.completed);
      expect(container.read(runtimeStreamingPreviewStateProvider).isEmpty, isTrue);
      expect(container.read(runtimeAssistantDraftProvider), isNull);

      final persisted = await databaseHelper.getMessagesByGroup(groupId);
      final persistedAssistantMessages = persisted
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(persistedAssistantMessages, hasLength(1));
      expect(persistedAssistantMessages.single.text, '你好，世界');
      expect(persistedAssistantMessages.single.status, MessageStatus.completed);
    });

    test(
        'runtime preview response stays placeholder-free before final takeover',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final afterEventsGate = Completer<void>();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '你好，',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '世界',
          ),
        ],
        afterEventsGate: afterEventsGate,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      final sendFuture = container.read(chatSendCoordinatorProvider).sendMessage(
            '打一声招呼',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );

      await _waitForSendPhase(container, ChatSendPhase.streamingResponse);

      final turnId = harness.recordedTurns.single.id!;
      final dispatcher = container.read(turnProjectionDispatcherProvider);
      await dispatcher.dispatchPreviewEvent(
        StreamingMessageStartEvent(
          messageId: 'preview_1',
          runtimeMetadata: {
            'streamTraceId': 'trace_1',
            'streamTurnId': '$turnId',
          },
        ),
      );
      await dispatcher.dispatchPreviewEvent(
        StreamingContentBlockStartEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          blockType: StreamingContentBlockType.text,
          runtimeMetadata: {
            'streamTraceId': 'trace_1',
            'streamTurnId': '$turnId',
          },
        ),
      );
      await dispatcher.dispatchPreviewEvent(
        StreamingContentBlockDeltaEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '你好，世界',
          runtimeMetadata: {
            'streamTraceId': 'trace_1',
            'streamTurnId': '$turnId',
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(
        container
            .read(messagesProvider)
            .where((message) => message.role == MessageRole.assistant),
        isEmpty,
      );

      afterEventsGate.complete();
      await sendFuture.timeout(const Duration(seconds: 1));
    });

    test('final answer clears runtime preview before completed message settles',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '最终回答',
            payloadJson: const {'previewMessageId': 'preview_1'},
          ),
        ],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      final previewNotifier =
          container.read(runtimeStreamingPreviewStateProvider.notifier);
      previewNotifier.publish(
        const StreamingMessageStartEvent(messageId: 'preview_1'),
      );
      previewNotifier.publish(
        const StreamingContentBlockStartEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          blockType: StreamingContentBlockType.text,
        ),
      );
      previewNotifier.publish(
        const StreamingContentBlockDeltaEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '临时草稿',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(
        container.read(runtimeStreamingPreviewStateProvider).messages,
        hasLength(1),
      );

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '直接给我结果',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(container.read(runtimeStreamingPreviewStateProvider).isEmpty, isTrue);
      final assistant = container
          .read(messagesProvider)
          .lastWhere((message) => message.role == MessageRole.assistant);
      expect(assistant.text, '最终回答');
      expect(assistant.status, MessageStatus.completed);
    });

    test('explicit slash skill injects reminder before real user message in transcript', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '已按 verify workflow 继续处理。',
          ),
        ],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
        skillRuntimeService: _CatalogSkillRuntimeService(
          availableCatalog: const [
            SkillCatalogEntry(
              id: 'verify',
              name: 'verify',
              description: 'Run project verification after code changes.',
              qualifiedPath: '/skills/installed/verify',
              isEnabled: true,
            ),
          ],
          skillByLookup: const {
            'verify': _SkillFixture(
              id: 'verify',
              name: 'verify',
              description: 'Run project verification after code changes.',
              bodyText: 'After code changes, run tests before claiming success.',
              skillRootPath: '/skills/installed/verify',
              entryFilePath: '/skills/installed/verify/SKILL.md',
            ),
          },
        ),
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '/verify 请检查这次改动',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(harness.recordedTurns.single.userInput, '请检查这次改动');
      final runtimeContext = harness.recordedTurns.single.providerStateJson?['runtime_context']
          as Map<String, dynamic>?;
      expect(runtimeContext, isNotNull);
      expect(
        runtimeContext?['explicit_skill_reminder'],
        contains('### Skill: verify'),
      );

      final userMessages = container
          .read(messagesProvider)
          .where((message) => message.role == MessageRole.user)
          .toList(growable: false);
      expect(userMessages, hasLength(1));
      expect(userMessages.single.text, '请检查这次改动');
    });

    test('final answer stays after tool-use blocks in the projected timeline',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantReasoningDelta,
            role: MessageRole.assistant,
            content: '先分析是否需要外部信息。',
            payloadJson: const {'scope': 'general'},
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolExecutionStarted,
            role: MessageRole.assistant,
            content: '正在执行工具',
            payloadJson: const {
              'toolName': 'web_search',
              'arguments': {'query': 'FlutterAIChat'},
              'status': 'running',
              'summary': '正在执行工具',
              'requiresConfirmation': false,
              'stepId': 1,
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已获得搜索结果',
            payloadJson: const {
              'toolName': 'web_search',
              'status': 'success',
              'summary': '已获得搜索结果',
              'data': {'items': []},
              'stepId': 1,
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '这是最终回答。',
          ),
        ],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '帮我查一下',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final projection = ChatTimelineProjectionService().build(
        groupId: groupId,
        messages: container.read(messagesProvider),
      );
      final finalResponseIndex = projection.assistantBlocks.indexWhere(
        (block) =>
            block.type == AssistantTurnBlockType.finalResponse &&
            block.text == '这是最终回答。',
      );
      final toolResultIndex = projection.assistantBlocks.indexWhere(
        (block) => block.type == AssistantTurnBlockType.toolResultSummary,
      );

      expect(finalResponseIndex, greaterThan(toolResultIndex));
      expect(
        container
            .read(messagesProvider)
            .where((message) => message.role == MessageRole.assistant)
            .where((message) => message.contentType == MessageContentType.plainText),
        hasLength(1),
      );
    });

    test(
        'tool-use reasoning stays as a separate analysis message before workflow and is not folded into final answer',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantReasoningDelta,
            role: MessageRole.assistant,
            content: '先确认是否需要联网。',
            payloadJson: const {'scope': 'tool_use'},
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolExecutionStarted,
            role: MessageRole.assistant,
            content: '正在执行工具',
            payloadJson: const {
              'toolName': 'web_search',
              'arguments': {'query': 'FlutterAIChat'},
              'status': 'running',
              'summary': '正在执行工具',
              'requiresConfirmation': false,
              'stepId': 1,
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已获得搜索结果',
            payloadJson: const {
              'toolName': 'web_search',
              'status': 'success',
              'summary': '已获得搜索结果',
              'data': {'items': []},
              'stepId': 1,
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '这是最终回答。',
          ),
        ],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '帮我查一下',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final projection = ChatTimelineProjectionService().build(
        groupId: groupId,
        messages: container.read(messagesProvider),
      );
      final toolUseBlockIndex = projection.assistantBlocks.indexWhere(
        (block) =>
            block.type == AssistantTurnBlockType.analysis &&
            block.reasoningText == '先确认是否需要联网。' &&
            block.payload?['reasoningScope'] == 'tool_use',
      );
      final firstToolBlockIndex = projection.assistantBlocks.indexWhere(
        (block) =>
            block.type == AssistantTurnBlockType.toolWorkflow ||
            block.type == AssistantTurnBlockType.toolResultSummary,
      );
      final finalResponse = projection.assistantBlocks.firstWhere(
        (block) =>
            block.type == AssistantTurnBlockType.finalResponse &&
            block.text == '这是最终回答。',
      );

      expect(toolUseBlockIndex, isNonNegative);
      expect(firstToolBlockIndex, greaterThan(toolUseBlockIndex));
      expect(finalResponse.reasoningText, isNull);

      final assistantMessages = container
          .read(messagesProvider)
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(
        assistantMessages.any(
          (message) =>
              message.reasoningContent == '先确认是否需要联网。' &&
              message.payloadJson?['reasoningScope'] == 'tool_use' &&
              message.text.isEmpty,
        ),
        isTrue,
      );
    });

    test(
        'reasoning delta does not create an early final-answer placeholder before final answer stage',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantReasoningDelta,
            role: MessageRole.assistant,
            content: '先整理思路。',
            payloadJson: const {'scope': 'general'},
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '这是最终回答。',
          ),
        ],
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatSendCoordinatorProvider).sendMessage(
            '开始回答',
            scheduleAutoSummary: () {},
            cancelActiveStream:
                container.read(chatControllerProvider).cancelStreamSubscription,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final assistantMessages = container
          .read(messagesProvider)
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages, hasLength(1));
      expect(assistantMessages.single.text, '这是最终回答。');
      expect(assistantMessages.single.status, MessageStatus.completed);
      expect(assistantMessages.single.reasoningContent, '先整理思路。');

      final projection = ChatTimelineProjectionService().build(
        groupId: groupId,
        messages: container.read(messagesProvider),
      );
      expect(
        projection.assistantBlocks.any(
          (block) =>
              block.type == AssistantTurnBlockType.finalResponse &&
              block.text == '这是最终回答。' &&
              block.reasoningText == '先整理思路。',
        ),
        isTrue,
      );
    });

    test('cancelling a streaming assistant turn with run failure falls back to failed',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final afterEventsGate = Completer<void>();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '还在生成',
          ),
        ],
        afterEventsGate: afterEventsGate,
        runTurnFailureCode: 'max_iterations_reached',
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      final sendFuture = container.read(chatControllerProvider).sendMessage(
            '开始生成',
          );

      await _waitForSendPhase(container, ChatSendPhase.streamingResponse);
      container.read(chatControllerProvider).cancelStreamSubscription();
      afterEventsGate.complete();
      await sendFuture.timeout(const Duration(seconds: 1));

      expect(container.read(chatSendStateProvider).phase, ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);

      final persisted = await databaseHelper.getMessagesByGroup(groupId);
      final turns = await ChatTurnRepository(databaseHelper).getTurnsByGroup(
        groupId,
      );
      expect(turns, isNotEmpty);
      expect(turns.single.status, ChatTurnStatus.failed);
      expect(
        persisted.where((message) => message.role == MessageRole.assistant),
        isNotEmpty,
      );
    });

    test(
        'cancelStreamSubscription settles active send and marks turn cancelled without assistant placeholder',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final afterEventsGate = Completer<void>();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '正在生成中',
          ),
        ],
        afterEventsGate: afterEventsGate,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      final sendFuture = container.read(chatControllerProvider).sendMessage(
            '请开始生成',
          );

      await _waitForSendPhase(container, ChatSendPhase.streamingResponse);
      container.read(chatControllerProvider).cancelStreamSubscription();
      afterEventsGate.complete();
      await sendFuture.timeout(const Duration(seconds: 1));

      final assistant = container
          .read(messagesProvider)
          .where((message) => message.role == MessageRole.assistant)
          .lastOrNull;
      expect(assistant, isNotNull);
      expect(assistant!.status, MessageStatus.interrupted);
      expect(assistant.text.trim(), isNotEmpty);
      expect(container.read(streamSubscriptionProvider), isNull);
      expect(container.read(chatSendStateProvider).phase, ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);

      final turns = await ChatTurnRepository(databaseHelper).getTurnsByGroup(
        groupId,
      );
      expect(turns, isNotEmpty);
      expect(turns.single.status, ChatTurnStatus.cancelled);
      expect(turns.single.stopReason, 'cancelled_by_user');
    });

    test(
        'cancelled preview-driven response projects interrupted partial text',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final afterEventsGate = Completer<void>();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '正在生成中',
          ),
        ],
        afterEventsGate: afterEventsGate,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(
          title: 'group',
        ),
      );
      container.read(currentGroupProvider.notifier).state = ChatGroup(
            id: groupId,
            title: 'group',
          );

      final previewNotifier =
          container.read(runtimeStreamingPreviewStateProvider.notifier);
      previewNotifier.publish(
        const StreamingMessageStartEvent(messageId: 'preview_1'),
      );
      previewNotifier.publish(
        const StreamingContentBlockStartEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          blockType: StreamingContentBlockType.text,
        ),
      );
      previewNotifier.publish(
        const StreamingContentBlockDeltaEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:text',
          deltaType: StreamingContentDeltaType.text,
          value: '正在生成中',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));

      final sendFuture = container.read(chatControllerProvider).sendMessage(
            '请开始生成',
          );

      await _waitForSendPhase(container, ChatSendPhase.streamingResponse);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        container
            .read(messagesProvider)
            .where((message) => message.role == MessageRole.assistant),
        isEmpty,
      );

      container.read(chatControllerProvider).cancelStreamSubscription();
      afterEventsGate.complete();
      await sendFuture.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final assistant = container
          .read(messagesProvider)
          .lastWhere((message) => message.role == MessageRole.assistant);
      expect(assistant.text, '正在生成中');
      expect(assistant.status, MessageStatus.interrupted);
      expect(
        container.read(runtimeStreamingPreviewStateProvider).isEmpty,
        isTrue,
      );
    });

    test('cancelled turn during preparing appends visible cancellation summary',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final afterEventsGate = Completer<void>();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
        afterEventsGate: afterEventsGate,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      final sendFuture = container.read(chatControllerProvider).sendMessage(
            '请开始处理',
          );

      await _waitForSendPhase(container, ChatSendPhase.preparing);

      container.read(chatControllerProvider).cancelStreamSubscription();
      afterEventsGate.complete();
      await sendFuture.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final assistant = container
          .read(messagesProvider)
          .where((message) => message.role == MessageRole.assistant)
          .lastOrNull;
      if (assistant != null) {
        expect(
          assistant.text,
          '已停止本轮回答。你可以继续提问，或让我基于当前结果继续整理。',
        );
        expect(assistant.status, MessageStatus.interrupted);
      }
    });

    test('cancelled turn marks active tool workflow message as cancelled',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final afterEventsGate = Completer<void>();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
        afterEventsGate: afterEventsGate,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      final sendFuture = container.read(chatControllerProvider).sendMessage(
            '先搜索',
          );

      await _waitForSendPhase(container, ChatSendPhase.preparing);
      final toolMessage = ChatMessage(
        text: '正在执行工具：web_search',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.toolInvocation,
        payloadJson: {
          'toolName': 'web_search',
          'arguments': {'query': 'OpenAI'},
          'status': 'running',
          'summary': '正在执行工具：web_search',
          'requiresConfirmation': false,
        },
      );
      final toolMessageId =
          await databaseHelper.insertMessage(toolMessage, groupId);
      toolMessage.id = toolMessageId;
      container.read(messagesProvider.notifier).addMessage(toolMessage);

      container.read(chatControllerProvider).cancelStreamSubscription();
      afterEventsGate.complete();
      await sendFuture.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final cancelledToolMessage = container.read(messagesProvider).lastWhere(
            (message) =>
                message.contentType == MessageContentType.toolInvocation,
          );
      expect(cancelledToolMessage.text, '已取消工具执行');
      expect(cancelledToolMessage.payloadJson?['status'], 'cancelled');
    });

    test(
        'confirmToolInvocation resumes pending confirmation and settles the turn',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
        resumeAfterConfirmationEvents: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.toolExecutionStarted,
            role: MessageRole.system,
            content: '正在执行工具：创建提醒',
            payloadJson: {
              'toolName': 'create_reminder',
              'arguments': {'title': '开会'},
              'status': 'running',
              'summary': '正在执行工具：创建提醒',
              'requiresConfirmation': false,
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已创建提醒：开会',
            payloadJson: {
              'toolName': 'create_reminder',
              'status': 'success',
              'summary': '已创建提醒：开会',
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '提醒已经安排好了。',
          ),
        ],
        resumeAfterConfirmationFinalStatus: ChatTurnStatus.completed,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      final turnId = await ChatTurnRepository(databaseHelper).createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.awaitingToolConfirmation,
          userInput: '提醒我开会',
        ),
      );

      final confirmationMessage = ChatMessage(
        text: '请确认执行工具：创建提醒',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.actionConfirmation,
        payloadJson: {
          'toolName': 'create_reminder',
          'arguments': {'title': '开会'},
          'status': 'awaitingConfirmation',
          'summary': '请确认执行工具：创建提醒',
          'requiresConfirmation': true,
          'agentTurnId': turnId,
          traceTurnIdPayloadKey: 'trace-confirm-1',
        },
      );
      final messageId =
          await databaseHelper.insertMessage(confirmationMessage, groupId);
      confirmationMessage.id = messageId;
      container.read(messagesProvider.notifier).addMessage(confirmationMessage);

      await container.read(chatSendCoordinatorProvider).confirmToolInvocation(
            confirmationMessage,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(harness.resumeAfterConfirmationInvocations, hasLength(1));
      final resumedMessage = container
          .read(messagesProvider)
          .firstWhere((message) => message.id == messageId);
      expect(resumedMessage.text, '正在执行工具：创建提醒');
      expect(resumedMessage.contentType, MessageContentType.toolInvocation);
      expect(resumedMessage.payloadJson?['status'], 'running');

      final finalAnswer = container.read(messagesProvider).lastWhere(
            (message) =>
                message.role == MessageRole.assistant &&
                message.contentType == MessageContentType.plainText,
          );
      expect(finalAnswer.text, '提醒已经安排好了。');
      expect(container.read(chatSendStateProvider).phase, ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);
      expect(
        (await ChatTurnRepository(databaseHelper).getTurn(turnId))!.status,
        ChatTurnStatus.completed,
      );
    });

    test(
        'submitQuestionAnswers replaces prompt with result and completes resumed turn',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final harness = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
        resumeAfterQuestionAnsweredEvents: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userInteractionResult,
            role: MessageRole.system,
            content: 'User answered AskUserQuestion:\n- Storage: SQLite',
            payloadJson: {
              'answersByQuestionId': {'storage_layer': 'SQLite'},
              'providerCallId': 'ask_call_1',
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '建议采用 SQLite 方案。',
          ),
        ],
        resumeAfterQuestionAnsweredFinalStatus: ChatTurnStatus.completed,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      final turnId = await ChatTurnRepository(databaseHelper).createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.awaitingUserInteraction,
          userInput: '帮我确定存储方案',
        ),
      );

      final promptPayload = {
        'questions': const [
          {
            'id': 'storage_layer',
            'header': 'Storage',
            'question': 'Which storage layer should we use?',
            'multiSelect': false,
            'options': [
              {
                'label': 'SQLite',
                'description': 'Local relational store',
              },
            ],
          },
        ],
        'agentTurnId': turnId,
        'stepId': 9,
        'providerCallId': 'ask_call_1',
        traceTurnIdPayloadKey: 'trace-ask-1',
      };
      final promptMessage = ChatMessage(
        text: '请先回答几个问题',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.askUserQuestionPrompt,
        payloadJson: promptPayload,
      );
      final promptMessageId =
          await databaseHelper.insertMessage(promptMessage, groupId);
      promptMessage.id = promptMessageId;
      container.read(messagesProvider.notifier).addMessage(promptMessage);

      await container.read(chatSendCoordinatorProvider).submitQuestionAnswers(
            promptMessage,
            response: AskUserQuestionResponse.fromJson(const {
              'answersByQuestionId': {
                'storage_layer': 'SQLite',
              },
              'selectedOptionLabelsByQuestionId': {
                'storage_layer': ['SQLite'],
              },
              'freeTextAnswersByQuestionId': {},
            }),
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(harness.resumeAfterQuestionAnsweredRequests, hasLength(1));
      final resultMessage = container
          .read(messagesProvider)
          .firstWhere((message) => message.id == promptMessageId);
      expect(
        resultMessage.contentType,
        MessageContentType.askUserQuestionResult,
      );
      expect(
        resultMessage.text,
        'User answered AskUserQuestion:\n- Storage: SQLite',
      );
      expect(resultMessage.payloadJson?['status'], 'submitted');
      expect(
        resultMessage.payloadJson?['submittedAnswers'],
        isA<Map<String, dynamic>>(),
      );

      final finalAnswer = container.read(messagesProvider).lastWhere(
            (message) =>
                message.role == MessageRole.assistant &&
                message.contentType == MessageContentType.plainText,
          );
      expect(finalAnswer.text, '建议采用 SQLite 方案。');
      expect(container.read(chatSendStateProvider).phase, ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);
      expect(
        (await ChatTurnRepository(databaseHelper).getTurn(turnId))!.status,
        ChatTurnStatus.completed,
      );
    });
  });
}

int _testDatabaseCounter = 0;

DatabaseHelper _createTestDatabaseHelper() {
  _testDatabaseCounter += 1;
  return DatabaseHelper(
    databaseName: 'chat_send_coordinator_test_$_testDatabaseCounter.db',
  );
}

Future<ProviderContainer> _createContainer({
  required DatabaseHelper databaseHelper,
  required TurnHarness harness,
  SkillRuntimeService? skillRuntimeService,
  BaseLLM? llm,
  AppSettingsRepository? settingsRepository,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final resolvedSettingsRepository = settingsRepository ??
      AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => null,
  );
  final resolvedLlm = llm ?? _NoopBaseLLM();
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => databaseHelper),
      sharedPreferencesProvider.overrideWith((ref) => preferences),
      appSettingsRepositoryProvider
          .overrideWith((ref) => resolvedSettingsRepository),
      chatServiceProvider.overrideWith((ref) => ChatService(llm: resolvedLlm)),
      turnHarnessProvider.overrideWith((ref) => harness),
      if (skillRuntimeService != null)
        skillRuntimeServiceProvider.overrideWith((ref) => skillRuntimeService),
      if (skillRuntimeService == null)
        skillRuntimeServiceProvider.overrideWith(
          (ref) => _CatalogSkillRuntimeService(
            availableCatalog: const [],
            skillByLookup: const {},
          ),
        ),
      scrollControllerProvider.overrideWith((ref) => ScrollController()),
      textControllerProvider.overrideWith((ref) => TextEditingController()),
      focusNodeProvider.overrideWith((ref) => FocusNode()),
    ],
  );
}

Future<AppSettingsRepository> _createSettingsRepository({
  required String defaultProviderId,
  required String defaultModelId,
  required List<LlmProviderConfig> providers,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => LlmLocalDefaults(
      defaultProviderId: defaultProviderId,
      defaultModelId: defaultModelId,
      providers: providers,
    ),
  );
}

Future<void> _waitForAssistantStatus(
  ProviderContainer container,
  MessageStatus status,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    final messages = container.read(messagesProvider);
    final assistant =
        messages.where((message) => message.isAssistant).lastOrNull;
    if (assistant?.status == status) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for assistant status $status');
}

Future<void> _waitForSendPhase(
  ProviderContainer container,
  ChatSendPhase phase,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (container.read(sendPhaseProvider) == phase) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for send phase $phase');
}

class _FakeTurnHarness extends TurnHarness {
  final DatabaseHelper databaseHelper;
  final List<ChatEvent> events;
  final List<ChatTurn> recordedTurns = [];
  final List<ChatConfig> recordedConfigs = [];
  final Completer<void>? afterEventsGate;
  final String? runTurnFailureCode;
  final List<ChatEvent> resumeAfterConfirmationEvents;
  final ChatTurnStatus? resumeAfterConfirmationFinalStatus;
  final List<ChatEvent> resumeAfterQuestionAnsweredEvents;
  final ChatTurnStatus? resumeAfterQuestionAnsweredFinalStatus;
  final List<ToolInvocation> resumeAfterConfirmationInvocations = [];
  final List<AskUserQuestionRequest> resumeAfterQuestionAnsweredRequests = [];

  _FakeTurnHarness({
    required this.databaseHelper,
    required this.events,
    this.afterEventsGate,
    this.runTurnFailureCode,
    this.resumeAfterConfirmationEvents = const [],
    this.resumeAfterConfirmationFinalStatus,
    this.resumeAfterQuestionAnsweredEvents = const [],
    this.resumeAfterQuestionAnsweredFinalStatus,
  }) : super(
          plannerService: AgentPlannerService(llm: _NoopBaseLLM()),
          turnRepository: ChatTurnRepository(databaseHelper),
          eventRepository: ChatEventRepository(databaseHelper),
          transcriptBuilderService: TranscriptBuilderService(
            eventRepository: ChatEventRepository(databaseHelper),
          ),
          turnVerifier: TurnVerifier(),
          toolCallService: ToolCallService(
            toolExecutor: ToolExecutor(chatStorage: databaseHelper),
          ),
          chatStorage: databaseHelper,
        );

  @override
  Stream<ChatEvent> runTurn({
    required ChatTurn turn,
    required ChatConfig config,
  }) async* {
    recordedTurns.add(turn);
    recordedConfigs.add(config);
    for (final event in events) {
      yield ChatEvent(
        turnId: turn.id ?? event.turnId,
        groupId: turn.groupId,
        sequence: event.sequence,
        eventType: event.eventType,
        role: event.role,
        status: event.status,
        content: event.content,
        payloadJson: event.payloadJson,
        createdAt: event.createdAt,
      );
    }

    final gate = afterEventsGate;
    if (gate != null) {
      await gate.future;
    }

    final failureCode = runTurnFailureCode;
    if (failureCode != null && turn.id != null) {
      await ChatTurnRepository(databaseHelper).markFailed(
        turn.id!,
        errorMessage: failureCode,
      );
    }
  }

  @override
  Stream<ChatEvent> resumeAfterConfirmation({
    required int turnId,
    required ToolInvocation invocation,
    required ChatConfig config,
    bool trustTool = false,
  }) async* {
    resumeAfterConfirmationInvocations.add(invocation);
    for (final event in resumeAfterConfirmationEvents) {
      yield ChatEvent(
        turnId: turnId,
        groupId: event.groupId,
        sequence: event.sequence,
        eventType: event.eventType,
        role: event.role,
        status: event.status,
        content: event.content,
        payloadJson: event.payloadJson,
        createdAt: event.createdAt,
      );
    }
    final finalStatus = resumeAfterConfirmationFinalStatus;
    if (finalStatus == ChatTurnStatus.completed) {
      await ChatTurnRepository(databaseHelper).markCompleted(
        turnId,
        finalResponseText: resumeAfterConfirmationEvents.lastOrNull?.content,
      );
    } else if (finalStatus == ChatTurnStatus.failed) {
      await ChatTurnRepository(databaseHelper).markFailed(
        turnId,
        errorMessage: 'resume_after_confirmation_failed',
      );
    }
  }

  @override
  Stream<ChatEvent> resumeAfterQuestionAnswered({
    required int turnId,
    required AskUserQuestionRequest request,
    required AskUserQuestionResponse response,
    required ChatConfig config,
  }) async* {
    resumeAfterQuestionAnsweredRequests.add(request);
    for (final event in resumeAfterQuestionAnsweredEvents) {
      yield ChatEvent(
        turnId: turnId,
        groupId: event.groupId,
        sequence: event.sequence,
        eventType: event.eventType,
        role: event.role,
        status: event.status,
        content: event.content,
        payloadJson: event.payloadJson,
        createdAt: event.createdAt,
      );
    }
    final finalStatus = resumeAfterQuestionAnsweredFinalStatus;
    if (finalStatus == ChatTurnStatus.completed) {
      await ChatTurnRepository(databaseHelper).markCompleted(
        turnId,
        finalResponseText: resumeAfterQuestionAnsweredEvents.lastOrNull?.content,
      );
    } else if (finalStatus == ChatTurnStatus.failed) {
      await ChatTurnRepository(databaseHelper).markFailed(
        turnId,
        errorMessage: 'resume_after_question_failed',
      );
    }
  }
}

class _CatalogSkillRuntimeService extends SkillRuntimeService {
  _CatalogSkillRuntimeService({
    required this.availableCatalog,
    required this.skillByLookup,
  }) : super(
          storageService: SkillStorageService(
            rootDirectoryProvider: () async =>
                throw UnimplementedError('not used in this test'),
          ),
        );

  final List<SkillCatalogEntry> availableCatalog;
  final Map<String, _SkillFixture> skillByLookup;

  @override
  Future<List<SkillCatalogEntry>> listSkillCatalogEntries() async => availableCatalog;

  @override
  Future<SkillDescriptor?> loadSkillById(String skillId) async {
    final normalized = skillId.trim().toLowerCase();
    final fixture = skillByLookup[normalized];
    if (fixture == null) {
      return null;
    }
    return fixture.toDescriptor();
  }
}

class _SkillFixture {
  const _SkillFixture({
    required this.id,
    required this.name,
    required this.description,
    required this.bodyText,
    required this.skillRootPath,
    required this.entryFilePath,
  });

  final String id;
  final String name;
  final String description;
  final String bodyText;
  final String skillRootPath;
  final String entryFilePath;

  SkillDescriptor toDescriptor() {
    return SkillDescriptor(
      id: id,
      name: name,
      description: description,
      bodyText: bodyText,
      skillRootPath: skillRootPath,
      entryFilePath: entryFilePath,
      sourceType: SkillSourceType.localInstalled,
      isEnabled: true,
    );
  }
}

Future<void> _interruptLatestAssistant({
  required ProviderContainer container,
  required DatabaseHelper databaseHelper,
}) async {
  container.read(chatSendStateProvider.notifier).update(
        isGenerating: false,
        phase: ChatSendPhase.idle,
      );
  final assistant = container
      .read(messagesProvider)
      .where((message) => message.isAssistant)
      .lastOrNull;
  if (assistant?.id == null) {
    fail('Expected an assistant message to interrupt');
  }
  final assistantId = assistant!.id!;
  container
      .read(messagesProvider.notifier)
      .updateMessageStatus(assistantId, MessageStatus.interrupted);
  await databaseHelper.updateMessageStatus(
    assistantId,
    MessageStatus.interrupted,
  );
}

class _NoopBaseLLM implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async =>
      null;

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';

}

class _ImageUnsupportedBaseLLM extends _NoopBaseLLM {
  @override
  Map<String, dynamic> get config => const {
        'supportsImageInput': false,
      };
}
