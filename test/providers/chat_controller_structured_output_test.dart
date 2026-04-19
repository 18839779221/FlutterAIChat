import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_choice.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/response/structured_summary_card.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/response_parser_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatController.structureMessageForDebug', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('成功路径会生成新的结构化卡片助手消息', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(
          result: const StructuredSummaryParseResult.structured(
            StructuredSummaryCard(
              title: 'Weekly Summary',
              summary: 'A short summary',
              keyPoints: ['A'],
              actionItems: ['B'],
              risks: ['C'],
            ),
          ),
        ),
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      final sourceMessage = ChatMessage(
        id: -10,
        text: 'source text',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.plainText,
      );

      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      container.read(messagesProvider.notifier).setMessages([sourceMessage]);

      await container
          .read(chatControllerProvider)
          .structureMessageForDebug(sourceMessage);

      final messages = container.read(messagesProvider);
      final newMessage =
          messages.firstWhere((message) => message.id != sourceMessage.id);
      final persisted = await databaseHelper.getMessagesByGroup(groupId);
      final persistedMessage =
          persisted.singleWhere((message) => message.id == newMessage.id);

      expect(newMessage.contentType, MessageContentType.structuredCard);
      expect(newMessage.status, MessageStatus.completed);
      expect(newMessage.payloadJson, isNotNull);
      expect(newMessage.payloadJson?['title'], 'Weekly Summary');
      expect(persistedMessage.contentType, MessageContentType.structuredCard);
      expect(persistedMessage.payloadJson?['title'], 'Weekly Summary');

      await databaseHelper.deleteGroup(groupId);
    });

    test('回退路径会生成新的普通文本助手消息', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(
          result: const StructuredSummaryParseResult.fallback(),
        ),
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      final sourceMessage = ChatMessage(
        id: -11,
        text: 'source text',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.plainText,
      );

      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      container.read(messagesProvider.notifier).setMessages([sourceMessage]);

      await container
          .read(chatControllerProvider)
          .structureMessageForDebug(sourceMessage);

      final messages = container.read(messagesProvider);
      final newMessage =
          messages.firstWhere((message) => message.id != sourceMessage.id);
      final persisted = await databaseHelper.getMessagesByGroup(groupId);
      final persistedMessage =
          persisted.singleWhere((message) => message.id == newMessage.id);

      expect(newMessage.contentType, MessageContentType.plainText);
      expect(newMessage.status, MessageStatus.completed);
      expect(newMessage.text, '结构化整理失败，请重试。');
      expect(persistedMessage.contentType, MessageContentType.plainText);
      expect(persistedMessage.payloadJson, isNull);

      await databaseHelper.deleteGroup(groupId);
    });

    test('守卫路径不会对不支持的消息触发整理动作', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final chatService = _FakeChatService(
        result: const StructuredSummaryParseResult.fallback(),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      final unsupportedMessage = ChatMessage(
        id: -12,
        text: 'user text',
        role: MessageRole.user,
        status: MessageStatus.completed,
      );

      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      container
          .read(messagesProvider.notifier)
          .setMessages([unsupportedMessage]);

      await container
          .read(chatControllerProvider)
          .structureMessageForDebug(unsupportedMessage);

      expect(container.read(messagesProvider), [unsupportedMessage]);
      expect(await databaseHelper.getMessagesByGroup(groupId), isEmpty);
      expect(chatService.requestedSourceTexts, isEmpty);

      await databaseHelper.deleteGroup(groupId);
    });

    test('debug 成功标记会走真实服务链路并生成结构化卡片消息', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: ChatService(llm: _NoopBaseLLM()),
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      final sourceMessage = ChatMessage(
        id: -13,
        text:
            '${ChatService.debugStructuredSuccessMarker} source text for local structured success',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.plainText,
      );

      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      container.read(messagesProvider.notifier).setMessages([sourceMessage]);

      await container
          .read(chatControllerProvider)
          .structureMessageForDebug(sourceMessage);

      final messages = container.read(messagesProvider);
      final newMessage =
          messages.firstWhere((message) => message.id != sourceMessage.id);
      final persisted = await databaseHelper.getMessagesByGroup(groupId);
      final persistedMessage =
          persisted.singleWhere((message) => message.id == newMessage.id);

      expect(newMessage.contentType, MessageContentType.structuredCard);
      expect(newMessage.status, MessageStatus.completed);
      expect(newMessage.payloadJson?['title'], 'Debug Structured Summary');
      expect(persistedMessage.contentType, MessageContentType.structuredCard);
      expect(
        persistedMessage.payloadJson?['summary'],
        'Generated from the local debug structured-output shortcut.',
      );

      await databaseHelper.deleteGroup(groupId);
    });
  });
}

int _testDatabaseCounter = 0;

DatabaseHelper _createTestDatabaseHelper() {
  _testDatabaseCounter += 1;
  return DatabaseHelper(
    databaseName:
        'chat_controller_structured_output_test_$_testDatabaseCounter.db',
  );
}

ProviderContainer _createContainer({
  required DatabaseHelper databaseHelper,
  required ChatService chatService,
}) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => databaseHelper),
      chatServiceProvider.overrideWith((ref) => chatService),
      scrollControllerProvider.overrideWith((ref) => ScrollController()),
    ],
  );
}

class _FakeChatService extends ChatService {
  final StructuredSummaryParseResult result;
  final List<String> requestedSourceTexts = [];

  _FakeChatService({required this.result}) : super(llm: _NoopBaseLLM());

  @override
  Future<StructuredSummaryParseResult> structureMessageForDebug(
      String sourceText) async {
    requestedSourceTexts.add(sourceText);
    return result;
  }
}

class _NoopBaseLLM implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) =>
      const Stream.empty();

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async =>
      throw UnimplementedError();

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async =>
      null;

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async =>
      null;

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Future<String> structureSummaryCard(String sourceText) {
    throw UnimplementedError();
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}
