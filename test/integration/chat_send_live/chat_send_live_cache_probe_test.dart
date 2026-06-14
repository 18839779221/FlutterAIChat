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
      harness.clearLlmTraceEntries();

      final prompt = _buildLongStablePrompt(
        tail: 'Case=exact_repeat. Reply with EXACT_REPEAT_OK only.',
      );
      final messages = _summaryMessages(prompt);
      await harness.summarizeMessages(messages);
      await harness.summarizeMessages(messages);

      final stats = await _waitForPositiveCacheField(
        harness,
        fieldName: 'cachedInputTokens',
        apiStyle: 'responses',
      );
      expect(_hasPositiveCacheField(stats, 'cachedInputTokens'), isTrue);
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
      harness.clearLlmTraceEntries();

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

      final stats = await _waitForPositiveCacheField(
        harness,
        fieldName: 'cachedInputTokens',
        apiStyle: 'chatCompletions',
      );
      expect(_hasPositiveCacheField(stats, 'cachedInputTokens'), isTrue);
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
      harness.clearLlmTraceEntries();

      final prompt = _buildLongStablePrompt(
        tail: 'Case=anthropic_exact_repeat. Reply with ANTHROPIC_REPEAT_OK only.',
      );
      final messages = _summaryMessages(prompt);
      await harness.summarizeMessages(messages);
      await harness.summarizeMessages(messages);

      final stats = await _waitForPositiveCacheField(
        harness,
        fieldName: 'cacheReadInputTokens',
        apiStyle: 'anthropicMessages',
      );
      expect(_hasPositiveCacheField(stats, 'cacheReadInputTokens'), isTrue);
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
  for (var i = 0; i < 120; i += 1) {
    buffer.writeln(
      'Stable cache prefix segment $i: This is a repeated probe sentence for cache observation only.',
    );
  }
  return buffer.toString();
}

Future<List<Map<String, int?>>> _waitForPositiveCacheField(
  ChatSendLiveTestHarness harness, {
  required String fieldName,
  required String apiStyle,
}) async {
  for (var i = 0; i < 120; i += 1) {
    final traceValues = _traceCacheFields(
      harness.llmRequestDoneEvents(
        label: 'side_summary',
        apiStyle: apiStyle,
      ),
    );
    if (_hasPositiveCacheField(traceValues, fieldName)) {
      return traceValues;
    }
    final stats = await harness.readRecentCacheStats();
    final values = _recentCacheFields(stats);
    if (_hasPositiveCacheField(values, fieldName)) {
      return values;
    }
    final logText = await harness.readLogFileText();
    if (_hasPositiveCacheFieldInLog(logText, fieldName)) {
      return <Map<String, int?>>[
        <String, int?>{
          'cachedInputTokens': _readPositiveFieldFromLog(
            logText,
            'cachedInputTokens',
          ),
          'cacheReadInputTokens': _readPositiveFieldFromLog(
            logText,
            'cacheReadInputTokens',
          ),
        },
      ];
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final traceValues = _traceCacheFields(
    harness.llmRequestDoneEvents(
      label: 'side_summary',
      apiStyle: apiStyle,
    ),
  );
  if (traceValues.isNotEmpty) {
    return traceValues;
  }
  final stats = await harness.readRecentCacheStats();
  return _recentCacheFields(stats);
}

List<Map<String, int?>> _recentCacheFields(dynamic stats) {
  final recentRequests = stats.recentRequests as List<dynamic>;
  return recentRequests
      .map(
        (request) => <String, int?>{
          'cachedInputTokens': request.cachedInputTokens as int?,
          'cacheReadInputTokens': request.cacheReadInputTokens as int?,
        },
      )
      .toList(growable: false);
}

List<Map<String, int?>> _traceCacheFields(List<Map<String, dynamic>> events) {
  return events.map((entry) {
    final data = entry['data'] as Map<String, dynamic>;
    return <String, int?>{
      'cachedInputTokens': data['cachedInputTokens'] as int?,
      'cacheReadInputTokens': data['cacheReadInputTokens'] as int?,
    };
  }).toList(growable: false);
}

bool _hasPositiveCacheField(
  List<Map<String, int?>> values,
  String fieldName,
) {
  for (final item in values) {
    final value = item[fieldName];
    if (value != null && value > 0) {
      return true;
    }
  }
  return false;
}

bool _hasPositiveCacheFieldInLog(String logText, String fieldName) {
  return (_readPositiveFieldFromLog(logText, fieldName) ?? 0) > 0;
}

int? _readPositiveFieldFromLog(String logText, String fieldName) {
  final escapedFieldName = RegExp.escape(fieldName);
  final matches = RegExp('$escapedFieldName=(\\d+)').allMatches(logText);
  for (final match in matches) {
    final value = int.tryParse(match.group(1) ?? '');
    if (value != null && value > 0) {
      return value;
    }
  }
  return null;
}
