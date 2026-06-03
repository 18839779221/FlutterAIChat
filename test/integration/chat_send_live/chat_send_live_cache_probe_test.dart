import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_send_live_test_harness.dart';
import '../../test_utils/local_test_provider_selector.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test(
    'responses exact repeat shows cache-hit evidence in recent logs',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerStyle: ChatTurnProviderStyle.openaiResponses,
      );
      await harness.clearLogFile();

      final prompt = _buildLongStablePrompt(
        tail: 'Case=exact_repeat. Reply with EXACT_REPEAT_OK only.',
      );
      final messages = _summaryMessages(prompt);
      await harness.summarizeMessages(messages);
      await harness.summarizeMessages(messages);

      final logText = await _waitForPositiveCacheField(
        harness,
        fieldName: 'cachedInputTokens',
      );
      expect(_hasPositiveCacheField(logText, 'cachedInputTokens'), isTrue);
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );

  test(
    'chat completions stable prefix with dynamic tail shows cache-hit evidence in recent logs',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
      );
      await harness.clearLogFile();

      final prefix = _buildLongStablePrefix();
      await harness.summarizeMessages(
        _summaryMessages(
          '$prefix\n\nCase=stable_prefix_dynamic_tail\nTail=A\nReply with PREFIX_TAIL_A only.',
        ),
      );
      await harness.summarizeMessages(
        _summaryMessages(
          '$prefix\n\nCase=stable_prefix_dynamic_tail\nTail=B\nReply with PREFIX_TAIL_B only.',
        ),
      );

      final logText = await _waitForPositiveCacheField(
        harness,
        fieldName: 'cachedInputTokens',
      );
      expect(_hasPositiveCacheField(logText, 'cachedInputTokens'), isTrue);
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );

  test(
    'anthropic exact repeat shows cache-read evidence in recent logs',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
      );
      await harness.clearLogFile();

      final prompt = _buildLongStablePrompt(
        tail: 'Case=anthropic_exact_repeat. Reply with ANTHROPIC_REPEAT_OK only.',
      );
      final messages = _summaryMessages(prompt);
      await harness.summarizeMessages(messages);
      await harness.summarizeMessages(messages);

      final logText = await _waitForPositiveCacheField(
        harness,
        fieldName: 'cacheReadInputTokens',
      );
      expect(_hasPositiveCacheField(logText, 'cacheReadInputTokens'), isTrue);
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );
}

String _buildLongStablePrompt({required String tail}) {
  return '${_buildLongStablePrefix()}\n\n$tail';
}

List<ChatMessage> _summaryMessages(String prompt) {
  return [
    ChatMessage(
      text: prompt,
      role: MessageRole.user,
    ),
  ];
}

String _buildLongStablePrefix() {
  final buffer = StringBuffer();
  for (var i = 0; i < 220; i += 1) {
    buffer.writeln(
      'Stable cache prefix segment $i: This is a repeated probe sentence for cache observation only.',
    );
  }
  return buffer.toString();
}

Future<String> _waitForPositiveCacheField(
  ChatSendLiveTestHarness harness, {
  required String fieldName,
}) async {
  for (var i = 0; i < 40; i += 1) {
    final logText = await harness.readLogFileText();
    if (_hasPositiveCacheField(logText, fieldName)) {
      return logText;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return harness.readLogFileText();
}

bool _hasPositiveCacheField(String logText, String fieldName) {
  final escapedFieldName = RegExp.escape(fieldName);
  final matches = RegExp('$escapedFieldName=(\\d+)').allMatches(logText);
  for (final match in matches) {
    final raw = match.group(1);
    final value = raw == null ? null : int.tryParse(raw);
    if (value != null && value > 0) {
      return true;
    }
  }
  return false;
}
