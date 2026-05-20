import 'dart:async';
import 'dart:typed_data';

import 'package:ai_chat/controllers/voice_input_controller.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/models/speech/speech_input_config.dart';
import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/audio/audio_capture_service.dart';
import 'package:ai_chat/services/speech/speech_to_text_service.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(find.byKey(const ValueKey('chat-input-voice-button')), findsNothing);
  });

  testWidgets('chat input shows voice button when voice input controller is available', (
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

    expect(find.byKey(const ValueKey('chat-input-voice-button')), findsOneWidget);
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

  testWidgets('chat input does not show pending label while awaiting confirmation', (
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

  testWidgets('chat input does not show planner hint while preparing', (tester) async {
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

  testWidgets('chat input does not show tool running helper text', (tester) async {
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

  testWidgets('chat input shows slash skill suggestions and inserts selected skill token', (
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
              qualifiedPath: 'projectSettings:verify',
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

    await tester.enterText(find.byKey(const ValueKey('chat-input-field')), '/ver');
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-input-skill-suggestions')), findsOneWidget);
    expect(find.text('verify'), findsOneWidget);

    await tester.tap(find.text('verify'));
    await tester.pump();

    final textField = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-input-field')),
    );
    expect(textField.controller?.text, '/verify ');
  });
}

class _SpyChatController extends ChatController {
  _SpyChatController(
    super.ref, {
    required this.onCancel,
  })
      : super(
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

class _NoopChatSendCoordinator implements ChatSendCoordinator {
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
}

class _NoopChatSummaryController implements ChatSummaryController {
  @override
  void cancelAutoSummaryTimer() {}

  @override
  void scheduleAutoSummary() {}

  @override
  Future<String?> summarizeAndUpdateTitle() async => null;
}

class _NoopChatPreferencesController implements ChatPreferencesController {
  @override
  Future<void> setSystemPrompt(String? prompt) async {}
}

ContextWindowSnapshot _contextSnapshot(double ratio) {
  return ContextWindowSnapshot(
    modelName: 'GPT-5.4',
    maxContextTokens: 128000,
    usableInputBudget: 104000,
    compressionTriggerRatio: 0.8,
    totalEstimatedInputTokens: 70000,
    totalWindowUsageRatio: ratio,
    usableInputUsageRatio: 0.0,
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
