import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat/controllers/voice_input_controller.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat/send_message_request.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/models/speech/speech_input_config.dart';
import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/attachments/chat_attachment_picker_service.dart';
import 'package:ai_chat/services/attachments/chat_attachment_storage_service.dart';
import 'package:ai_chat/services/audio/audio_capture_service.dart';
import 'package:ai_chat/services/speech/speech_to_text_service.dart';
import 'package:ai_chat/services/session_context_service.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('chat input shows compact reply tray when idle', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chat-input-dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-input-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-input-bottom-bar')), findsOneWidget);
    expect(find.text('Balanced · 可追溯输出'), findsNothing);
    expect(find.text('深度'), findsNothing);
    expect(find.text('简洁'), findsNothing);
    expect(find.byKey(const ValueKey('chat-input-idle-note')), findsNothing);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    final textField = tester
        .widget<TextField>(find.byKey(const ValueKey('chat-input-field')));
    expect(textField.minLines, 1);
    expect(textField.maxLines, 4);
    expect(textField.textAlignVertical, TextAlignVertical.center);
    expect(find.byKey(const ValueKey('chat-input-voice-button')), findsNothing);

    final composerShell = tester.widget<Container>(
      find.byKey(const ValueKey('chat-input-composer-shell')),
    );
    expect(composerShell.decoration, isNull);

    final dock = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('chat-input-dock')),
    );
    final decoration = dock.decoration as BoxDecoration;
    final gradient = decoration.gradient as LinearGradient?;
    final boxShadow = decoration.boxShadow;
    expect(gradient, isNotNull);
    expect(gradient!.colors, hasLength(3));
    expect(
      (gradient.colors.first.a * 255.0).round(),
      lessThan((gradient.colors.last.a * 255.0).round()),
    );
    expect(
      (gradient.colors.last.a * 255.0).round(),
      lessThan(255),
    );
    expect(boxShadow, isNotNull);
    expect(boxShadow, hasLength(3));
    expect(boxShadow!.first.blurRadius, greaterThanOrEqualTo(30));
    expect(boxShadow.first.spreadRadius, greaterThan(0));
    expect(boxShadow[1].color.a, greaterThan(boxShadow.first.color.a));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('chat input dock exposes a unified focus surface',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final focusNode = container.read(focusNodeProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(focusNode.hasFocus, isFalse);
    final focusSurface = find.byKey(const ValueKey('chat-input-focus-surface'));
    expect(focusSurface, findsOneWidget);

    await tester.tapAt(tester.getRect(focusSurface).center);
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets(
      'chat input shows voice button when voice input controller is available',
      (
    tester,
  ) async {
    final harness = _VoiceControllerHarness.create();
    final container = ProviderContainer(
      overrides: [
        textControllerProvider.overrideWithValue(
          harness.controller.textController,
        ),
        voiceInputControllerProvider.overrideWithValue(
          harness.controller,
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      harness.controller.dispose();
      await harness.controller.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('chat-input-voice-button')), findsOneWidget);
  });

  testWidgets('chat input updates the shared text field while listening', (
    tester,
  ) async {
    final harness = _VoiceControllerHarness.create();
    final container = ProviderContainer(
      overrides: [
        textControllerProvider.overrideWithValue(
          harness.controller.textController,
        ),
        voiceInputControllerProvider.overrideWithValue(
          harness.controller,
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      harness.controller.dispose();
      await harness.controller.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await harness.controller.pressStart();
    harness.speech.emitPartial('明天上午十点');
    await tester.pump();

    final textField = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-input-field')),
    );
    expect(textField.controller!.text, '明天上午十点');
    expect(find.byKey(const ValueKey('chat-input-voice-draft')), findsNothing);
  });

  testWidgets('chat input shows active recording visuals while listening', (
    tester,
  ) async {
    final harness = _VoiceControllerHarness.create();
    final container = ProviderContainer(
      overrides: [
        textControllerProvider.overrideWithValue(
          harness.controller.textController,
        ),
        voiceInputControllerProvider.overrideWithValue(
          harness.controller,
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      harness.controller.dispose();
      await harness.controller.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    await harness.controller.pressStart();
    await tester.pump();

    expect(find.text('正在聆听'), findsOneWidget);

    final colors = Theme.of(
      tester.element(find.byType(ChatInput)),
    ).extension<AppThemeSpec>()!;
    final micContainer = tester.widget<Container>(
      find.byKey(const ValueKey('chat-input-voice-button-shell')),
    );
    final micDecoration = micContainer.decoration! as BoxDecoration;
    expect(micDecoration.color, colors.workflowRunning.withValues(alpha: 0.16));
  });

  testWidgets('chat input keeps second row reserved for context usage info', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        contextWindowSnapshotProvider.overrideWith(
          (ref) async => _contextSnapshot(0.54),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-input-bottom-bar')), findsOneWidget);
    expect(find.text('54%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('context-window-usage-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('chat input shows current model chip before token usage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'aigocode',
        defaultModelId: 'gpt-4o-mini',
        providers: [
          LlmProviderConfig(
            id: 'aigocode',
            name: 'AIGoCode',
            apiKey: 'key',
            baseUrl: 'https://api.aigocode.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
        contextWindowSnapshotProvider.overrideWith(
          (ref) async => _contextSnapshot(0.54),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-input-model-chip')), findsOneWidget);
    expect(find.text('gpt-4o-mini'), findsOneWidget);
    expect(find.text('54%'), findsOneWidget);
  });

  testWidgets('chat input shows unconfigured model chip when no model selected',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => null,
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-input-model-chip')), findsOneWidget);
    expect(find.text('未配置模型'), findsOneWidget);
  });

  testWidgets(
      'chat input model menu closes on outside tap without opening provider submenu',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'aigocode',
        defaultModelId: 'gpt-4o-mini',
        providers: [
          LlmProviderConfig(
            id: 'aigocode',
            name: 'AIGoCode',
            apiKey: 'key',
            baseUrl: 'https://api.aigocode.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
              LlmProviderModel(id: 'gpt-5.4', name: ''),
            ],
          ),
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'key',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4.1', name: ''),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chat-input-model-chip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-input-model-menu')), findsOneWidget);
    expect(find.text('AIGoCode'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-input-model-menu')), findsNothing);
    expect(find.text('AIGoCode'), findsNothing);
  });

  testWidgets('chat input model chip updates immediately after selecting model',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'aigocode',
        defaultModelId: 'gpt-4o-mini',
        providers: [
          LlmProviderConfig(
            id: 'aigocode',
            name: 'AIGoCode',
            apiKey: 'key',
            baseUrl: 'https://api.aigocode.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
              LlmProviderModel(id: 'gpt-5.4', name: ''),
            ],
          ),
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'key',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4.1', name: ''),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('gpt-4o-mini'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-input-model-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-5.4').last);
    await tester.pumpAndSettle();

    expect(find.text('gpt-5.4'), findsOneWidget);
    expect(find.text('gpt-4o-mini'), findsNothing);
  });

  testWidgets(
      'chat input model chip updates immediately after switching provider and selecting model',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'aigocode',
        defaultModelId: 'gpt-4o-mini',
        providers: [
          LlmProviderConfig(
            id: 'aigocode',
            name: 'AIGoCode',
            apiKey: 'key',
            baseUrl: 'https://api.aigocode.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
            ],
          ),
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'key',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4.1', name: ''),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('gpt-4o-mini'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-input-model-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AIGoCode').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-4.1').last);
    await tester.pumpAndSettle();

    expect(find.text('gpt-4.1'), findsOneWidget);
    expect(find.text('gpt-4o-mini'), findsNothing);
  });

  testWidgets(
      'chat input model menu opens on selected provider when it differs from default',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'aigocode',
        defaultModelId: 'gpt-4o-mini',
        providers: [
          LlmProviderConfig(
            id: 'aigocode',
            name: 'AIGoCode',
            apiKey: 'key',
            baseUrl: 'https://api.aigocode.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
              LlmProviderModel(id: 'gpt-5.4', name: ''),
            ],
          ),
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'key',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4.1', name: ''),
            ],
          ),
        ],
      ),
    );
    await settingsRepository.selectProviderAndModel(
      providerId: 'openai',
      modelId: 'gpt-4.1',
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('gpt-4.1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-input-model-chip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-input-model-menu')), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('gpt-4.1'), findsNWidgets(2));
    expect(find.text('gpt-4o-mini'), findsNothing);
  });

  testWidgets(
      'chat input syncs draft session provider style after switching model provider',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'claude',
        defaultModelId: 'claude-sonnet',
        providers: [
          LlmProviderConfig(
            id: 'claude',
            name: 'Claude',
            apiKey: 'key',
            baseUrl: 'https://example.com/v1/messages',
            models: [
              LlmProviderModel(id: 'claude-sonnet', name: ''),
            ],
          ),
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'key',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4.1', name: ''),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentGroupProvider.notifier).state = ChatGroup(
      title: '新对话 1',
      lockedProviderStyle: ChatTurnProviderStyle.anthropicMessages,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chat-input-model-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-4.1').last);
    await tester.pumpAndSettle();

    expect(
      container.read(currentGroupProvider)?.lockedProviderStyle,
      ChatTurnProviderStyle.openaiResponses,
    );
  });

  testWidgets(
      'chat input does not sync persisted session provider style after switching model provider',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'claude',
        defaultModelId: 'claude-sonnet',
        providers: [
          LlmProviderConfig(
            id: 'claude',
            name: 'Claude',
            apiKey: 'key',
            baseUrl: 'https://example.com/v1/messages',
            models: [
              LlmProviderModel(id: 'claude-sonnet', name: ''),
            ],
          ),
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'key',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4.1', name: ''),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentGroupProvider.notifier).state = ChatGroup(
      id: 1,
      title: '已有对话',
      lockedProviderStyle: ChatTurnProviderStyle.anthropicMessages,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chat-input-model-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-4.1').last);
    await tester.pumpAndSettle();

    expect(
      container.read(currentGroupProvider)?.lockedProviderStyle,
      ChatTurnProviderStyle.anthropicMessages,
    );
  });

  testWidgets(
      'chat input does not show pending label while awaiting confirmation', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.awaitingConfirmation,
              isGenerating: false,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('等待工具确认'), findsNothing);
  });

  testWidgets('chat input does not show planner hint while preparing',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.preparing,
              isGenerating: false,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('正在规划下一步'), findsNothing);
  });

  testWidgets('chat input shows stop icon and cancels while preparing', (
    tester,
  ) async {
    var cancelCount = 0;
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.preparing,
              isGenerating: false,
            ),
        ),
        chatControllerProvider.overrideWith(
          (ref) => _SpyChatController(ref, onCancel: () => cancelCount += 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byType(FilledButton));
    expect(cancelCount, 1);
  });

  testWidgets('chat input does not show tool running helper text',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.executingTool,
              isGenerating: false,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('工具执行中'), findsNothing);
  });

  testWidgets('chat input shows stop icon and cancels while executing tool', (
    tester,
  ) async {
    var cancelCount = 0;
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.executingTool,
              isGenerating: false,
            ),
        ),
        chatControllerProvider.overrideWith(
          (ref) => _SpyChatController(ref, onCancel: () => cancelCount += 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byType(FilledButton));
    expect(cancelCount, 1);
  });

  testWidgets('chat input shows stop icon instead of spinner while streaming', (
    tester,
  ) async {
    var cancelCount = 0;
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.streamingResponse,
              isGenerating: true,
            ),
        ),
        chatControllerProvider.overrideWith(
          (ref) => _SpyChatController(ref, onCancel: () => cancelCount += 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byType(FilledButton));
    expect(cancelCount, 1);
  });

  testWidgets(
      'chat input shows slash skill suggestions and inserts selected skill token',
      (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        enabledSkillCatalogProvider.overrideWith(
          (ref) async => const [
            SkillCatalogEntry(
              id: 'verify',
              name: 'verify',
              description: 'Run project verification after code changes.',
              qualifiedPath: '/skills/installed/verify',
              isEnabled: true,
            ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
        find.byKey(const ValueKey('chat-input-field')), '/ver');
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-input-skill-suggestions')),
        findsOneWidget);
    expect(find.text('verify'), findsOneWidget);

    await tester.tap(find.text('verify'));
    await tester.pump();

    final textField = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-input-field')),
    );
    expect(textField.controller?.text, '/verify ');
  });

  testWidgets('chat input shows compact slash command suggestions', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chat-input-field')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '/comp',
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-input-composer-shell')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-input-skill-suggestions')),
      findsOneWidget,
    );
    expect(find.text('/compact'), findsOneWidget);
  });

  testWidgets('chat input closes slash suggestion overlay on outside tap', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chat-input-field')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '/comp',
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('chat-input-skill-suggestions')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-input-skill-suggestions')),
      findsNothing,
    );
  });

  testWidgets('chat input submits compact command without sending message', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatControllerProvider.overrideWith(
          (ref) => _RecordingCompactChatController(ref),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '/compact',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final controller = container.read(chatControllerProvider)
        as _RecordingCompactChatController;
    expect(controller.compactCount, 1);
    expect(controller.sentRequests, isEmpty);
  });

  testWidgets('chat input rejects compact command when attachments exist', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatControllerProvider.overrideWith(
          (ref) => _RecordingCompactChatController(ref),
        ),
        chatAttachmentPickerServiceProvider.overrideWithValue(
          _FakeAttachmentPickerService(
            attachments: [
              ChatAttachment.image(
                localId: 'att-1',
                fileName: 'demo.png',
                mimeType: 'image/png',
                byteSize: 128,
                status: ChatAttachmentStatus.selected,
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chat-input-add-image')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '/compact',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    final controller = container.read(chatControllerProvider)
        as _RecordingCompactChatController;
    expect(controller.compactCount, 0);
    expect(controller.sentRequests, isEmpty);
    expect(find.text('压缩历史上下文前请先移除附件。'), findsOneWidget);
  });

  testWidgets('chat input opens picker and renders selected image', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatAttachmentPickerServiceProvider.overrideWithValue(
          _FakeAttachmentPickerService(
            attachments: [
              ChatAttachment.image(
                localId: 'att-1',
                fileName: 'demo.png',
                mimeType: 'image/png',
                byteSize: 128,
                status: ChatAttachmentStatus.selected,
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chat-input-add-image')));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-input-attachment-strip')),
        findsOneWidget);
    expect(find.text('demo.png'), findsNothing);
  });

  testWidgets(
      'chat input persists picked images before rendering composer attachments',
      (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatAttachmentPickerServiceProvider.overrideWithValue(
          _FakeAttachmentPickerService(
            attachments: [
              ChatAttachment.image(
                localId: 'att-1',
                fileName: 'demo.png',
                mimeType: 'image/png',
                byteSize: 128,
                localPath: '/tmp/picked-demo.png',
                status: ChatAttachmentStatus.selected,
              ),
            ],
          ),
        ),
        chatAttachmentStorageServiceProvider.overrideWithValue(
          _RecordingAttachmentStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chat-input-add-image')));
    await tester.pump();

    final storage = container.read(chatAttachmentStorageServiceProvider)
        as _RecordingAttachmentStorageService;
    expect(storage.receivedAttachments, hasLength(1));
    expect(
        storage.receivedAttachments.single.localPath, '/tmp/picked-demo.png');
    expect(
      find.byKey(const ValueKey('chat-input-attachment-strip')),
      findsOneWidget,
    );
  });

  testWidgets('chat input sends request with selected image attachments', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'vision',
        defaultModelId: 'vision-model',
        providers: [
          LlmProviderConfig(
            id: 'vision',
            name: 'Vision Provider',
            apiKey: 'key',
            baseUrl: 'https://vision.example/v1',
            models: [
              LlmProviderModel(
                id: 'vision-model',
                name: 'Vision Model',
                supportsImageInput: true,
              ),
            ],
          ),
        ],
      ),
    );
    final sendCoordinator = _CompletingChatSendCoordinator();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
        chatAttachmentPickerServiceProvider.overrideWithValue(
          _FakeAttachmentPickerService(
            attachments: [
              ChatAttachment.image(
                localId: 'att-1',
                fileName: 'demo.png',
                mimeType: 'image/png',
                byteSize: 128,
                status: ChatAttachmentStatus.selected,
              ),
            ],
          ),
        ),
        chatControllerProvider.overrideWith(
          (ref) => ChatController(
            ref,
            sendCoordinator: sendCoordinator,
            sessionCoordinator: _NoopChatSessionCoordinator(),
            summaryController: _NoopChatSummaryController(),
            preferencesController: _NoopChatPreferencesController(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chat-input-add-image')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '看下这张图',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(sendCoordinator.lastRequest?.attachments, hasLength(1));
    expect(sendCoordinator.lastRequest?.text, '看下这张图');
    expect(
      find.byKey(const ValueKey('chat-input-attachment-strip')),
      findsNothing,
    );

    sendCoordinator.complete();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('chat-input-attachment-strip')),
      findsNothing,
    );
  });

  testWidgets(
      'chat input asks for confirmation before sending image on unsupported model',
      (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'beehears-responses',
        defaultModelId: 'gpt-5.4',
        providers: [
          LlmProviderConfig(
            id: 'beehears-responses',
            name: 'BeeHears Responses',
            apiKey: 'key',
            baseUrl: 'https://ai.beehears.com/v1',
            models: [
              LlmProviderModel(
                id: 'gpt-5.4',
                name: 'gpt-5.4',
                supportsImageInput: false,
              ),
            ],
          ),
        ],
      ),
    );
    final sendCoordinator = _CompletingChatSendCoordinator();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
        chatAttachmentPickerServiceProvider.overrideWithValue(
          _FakeAttachmentPickerService(
            attachments: [
              ChatAttachment.image(
                localId: 'att-1',
                fileName: 'demo.png',
                mimeType: 'image/png',
                byteSize: 128,
                status: ChatAttachmentStatus.selected,
              ),
            ],
          ),
        ),
        chatControllerProvider.overrideWith(
          (ref) => ChatController(
            ref,
            sendCoordinator: sendCoordinator,
            sessionCoordinator: _NoopChatSessionCoordinator(),
            summaryController: _NoopChatSummaryController(),
            preferencesController: _NoopChatPreferencesController(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chat-input-add-image')));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('当前模型可能不支持图片输入，仍然尝试发送？'), findsOneWidget);
    expect(sendCoordinator.lastRequest, isNull);

    await tester.tap(find.text('仍然发送'));
    await tester.pump();

    expect(sendCoordinator.lastRequest?.attachments, hasLength(1));
    expect(
      sendCoordinator.lastRequest?.allowUnsupportedImageInputAttempt,
      isTrue,
    );
  });
}

class _SpyChatController extends ChatController {
  _SpyChatController(
    super.ref, {
    required this.onCancel,
  }) : super(
          sendCoordinator: _NoopChatSendCoordinator(),
          sessionCoordinator: _NoopChatSessionCoordinator(),
          summaryController: _NoopChatSummaryController(),
          preferencesController: _NoopChatPreferencesController(),
        );

  final VoidCallback onCancel;

  @override
  void cancelStreamSubscription() {
    onCancel();
  }
}

class _RecordingCompactChatController extends ChatController {
  _RecordingCompactChatController(
    super.ref,
  ) : super(
          sendCoordinator: _NoopChatSendCoordinator(),
          sessionCoordinator: _NoopChatSessionCoordinator(),
          summaryController: _NoopChatSummaryController(),
          preferencesController: _NoopChatPreferencesController(),
        );

  final List<SendMessageRequest> sentRequests = <SendMessageRequest>[];
  int compactCount = 0;

  @override
  Future<void> sendMessageRequest(SendMessageRequest request) async {
    sentRequests.add(request);
  }

  @override
  Future<ManualSessionCompactionResult> compactCurrentSession() async {
    compactCount += 1;
    return const ManualSessionCompactionResult(
      snapshot: null,
      didCompactHistory: true,
    );
  }
}

class _NoopChatSendCoordinator implements ChatSendCoordinator {
  @override
  Future<void> sendMessageRequest(
    SendMessageRequest request, {
    required void Function() scheduleAutoSummary,
    required void Function() cancelActiveStream,
  }) async {}

  @override
  Future<void> cancelToolInvocation(ChatMessage message) async {}

  @override
  Future<void> confirmToolInvocation(
    ChatMessage message, {
    bool trustTool = false,
  }) async {}

  @override
  Future<void> sendMessage(
    String text, {
    required void Function() scheduleAutoSummary,
    required void Function() cancelActiveStream,
  }) async {}

  @override
  Future<void> submitQuestionAnswers(
    ChatMessage message, {
    required AskUserQuestionResponse response,
  }) async {}
}

class _RecordingChatSendCoordinator extends _NoopChatSendCoordinator {
  SendMessageRequest? lastRequest;

  @override
  Future<void> sendMessageRequest(
    SendMessageRequest request, {
    required void Function() scheduleAutoSummary,
    required void Function() cancelActiveStream,
  }) async {
    lastRequest = request;
  }
}

class _CompletingChatSendCoordinator extends _RecordingChatSendCoordinator {
  final Completer<void> _completer = Completer<void>();

  @override
  Future<void> sendMessageRequest(
    SendMessageRequest request, {
    required void Function() scheduleAutoSummary,
    required void Function() cancelActiveStream,
  }) async {
    await super.sendMessageRequest(
      request,
      scheduleAutoSummary: scheduleAutoSummary,
      cancelActiveStream: cancelActiveStream,
    );
    return _completer.future;
  }

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

class _NoopChatSessionCoordinator implements ChatSessionCoordinator {
  @override
  Future<void> createNewGroup() async {}

  @override
  Future<void> deleteGroup(int id) async {}

  @override
  Future<void> loadCurrentGroup() async {}

  @override
  Future<void> loadGroups() async {}

  @override
  Future<void> loadMessages() async {}

  @override
  Future<void> loadMoreMessages() async {}

  @override
  Future<void> selectGroup(ChatGroup group) async {}

  @override
  Future<void> updateCurrentGroupWorkspace(String? workspaceId) async {}

  @override
  Future<void> syncDraftGroupProviderStyle() async {}
}

class _NoopChatSummaryController implements ChatSummaryController {
  @override
  void cancelAutoSummaryTimer() {}

  @override
  void scheduleAutoSummary() {}

  @override
  Future<String?> summarizeAndUpdateTitle() async => null;
}

class _FakeAttachmentPickerService implements ChatAttachmentPickerService {
  _FakeAttachmentPickerService({
    required this.attachments,
  });

  final List<ChatAttachment> attachments;

  @override
  Future<List<ChatAttachment>> pickImages() async => attachments;
}

class _RecordingAttachmentStorageService extends ChatAttachmentStorageService {
  _RecordingAttachmentStorageService()
      : super(
          resolveRootDirectory: () async => Directory.systemTemp,
        );

  final List<ChatAttachment> receivedAttachments = [];

  @override
  Future<ChatAttachment> persistSelectedImage({
    required ChatAttachment attachment,
  }) async {
    receivedAttachments.add(attachment);
    return attachment.copyWith(
      fileName: 'persisted-${attachment.fileName}',
      localPath: '/managed/${attachment.fileName}',
      thumbnailPath: '/managed/thumbs/${attachment.fileName}',
      status: ChatAttachmentStatus.ready,
    );
  }
}

class _NoopChatPreferencesController implements ChatPreferencesController {
  @override
  Future<void> setSystemPrompt(String? prompt) async {}
}

ContextWindowSnapshot _contextSnapshot(double ratio) {
  return ContextWindowSnapshot(
    modelName: 'GPT-5.4',
    maxContextTokens: 128000,
    effectiveInputBudget: 104000,
    autoCompactTriggerTokens: 91000,
    totalEstimatedInputTokens: 70000,
    plannerInputUsageRatio: 0.0,
    totalWindowUsageRatio: ratio,
    effectiveInputUsageRatio: 0.0,
    didCompactHistory: false,
    recentCompletedTurnCount: 0,
    segments: const <ContextWindowSegment>[],
  );
}

class _VoiceControllerHarness {
  final VoiceInputController controller;
  final _FakeSpeechToTextService speech;
  final _FakeAudioCaptureService audio;

  _VoiceControllerHarness._({
    required this.controller,
    required this.speech,
    required this.audio,
  });

  factory _VoiceControllerHarness.create() {
    final speech = _FakeSpeechToTextService();
    final audio = _FakeAudioCaptureService();
    final controller = VoiceInputController(
      textController: TextEditingController(),
      speechInputConfig: const SpeechInputConfig(
        enabled: true,
        provider: 'aliyun',
        endpoint: 'wss://speech.example/ws',
        apiKey: 'speech-key',
        sampleRate: 16000,
        languageHints: ['zh', 'en'],
      ),
      speechToTextService: speech,
      audioCaptureService: audio,
    );
    return _VoiceControllerHarness._(
      controller: controller,
      speech: speech,
      audio: audio,
    );
  }
}

class _FakeSpeechToTextService implements SpeechToTextService {
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();
  final StreamController<String> _finalController =
      StreamController<String>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();

  @override
  Stream<Object> get errors => _errorController.stream;

  @override
  Stream<String> get finalResults => _finalController.stream;

  @override
  Stream<String> get partialResults => _partialController.stream;

  @override
  Future<void> close() async {}

  void emitPartial(String text) {
    _partialController.add(text);
  }

  @override
  Future<void> finishSession() async {}

  @override
  Future<void> sendAudioFrame(Uint8List frame) async {}

  @override
  Future<void> startSession() async {}
}

class _FakeAudioCaptureService implements AudioCaptureService {
  @override
  Stream<Uint8List> get audioFrames => const Stream<Uint8List>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start({required int sampleRate}) async {}

  @override
  Future<void> stop() async {}
}
