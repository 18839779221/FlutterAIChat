import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';

class SelectedHeadlessLiveProvider {
  /// Concrete provider chosen for the current test run.
  final LlmProviderConfig provider;

  /// Human-readable reason emitted into test logs for visibility.
  final String selectionReason;

  const SelectedHeadlessLiveProvider({
    required this.provider,
    required this.selectionReason,
  });
}

String? resolveInjectedLocalDefaultsPath({
  Map<String, String>? environment,
}) {
  final resolvedEnvironment = environment ?? Platform.environment;
  for (final key in const ['LIVE_LLM_LOCAL_DEFAULTS_PATH', 'LOCAL_DEFAULTS_PATH']) {
    final value = resolvedEnvironment[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

LlmLocalDefaults? loadInjectedLocalDefaults({
  Map<String, String>? environment,
  List<String> fallbackRelativePaths = const [
    'config/local_defaults.json',
    '../../config/local_defaults.json',
  ],
}) {
  final injectedPath = resolveInjectedLocalDefaultsPath(
    environment: environment,
  );
  final candidates = <File>[
    if (injectedPath != null) File(injectedPath),
    ...fallbackRelativePaths.map(File.new),
  ];
  File? file;
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      file = candidate;
      break;
    }
  }
  if (file == null) {
    return null;
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    return null;
  }
  return LlmLocalDefaults.fromJson(Map<String, dynamic>.from(decoded));
}

SelectedHeadlessLiveProvider selectHeadlessLiveProvider({
  required LlmLocalDefaults defaults,
  required ChatTurnProviderStyle style,
  Map<String, String>? environment,
  ApiProtocolResolver protocolResolver = const ApiProtocolResolver(),
}) {
  final resolvedEnvironment = environment ?? Platform.environment;
  final overrideId = _styleOverrideKey(style, resolvedEnvironment);
  if (overrideId != null) {
    final provider = defaults.providers.where((item) => item.id == overrideId).firstOrNull;
    if (provider == null) {
      throw StateError(
        'Injected provider "$overrideId" from ${_styleEnvKey(style)} was not found in local defaults.',
      );
    }
    return SelectedHeadlessLiveProvider(
      provider: provider,
      selectionReason: 'selected from ${_styleEnvKey(style)} override',
    );
  }

  final matchingProviders = defaults.providers
      .where((item) => _matchesStyle(item, style, protocolResolver))
      .toList(growable: false);
  if (matchingProviders.isEmpty) {
    throw StateError('No provider matched style $style in local defaults.');
  }

  final preferredIds = _preferredProviderIds(style);
  for (final preferredId in preferredIds) {
    final provider = matchingProviders.where((item) => item.id == preferredId).firstOrNull;
    if (provider != null) {
      return SelectedHeadlessLiveProvider(
        provider: provider,
        selectionReason: 'selected preferred provider for $style',
      );
    }
  }

  final defaultProviderId = defaults.defaultProviderId;
  if (defaultProviderId != null) {
    final provider = matchingProviders.where((item) => item.id == defaultProviderId).firstOrNull;
    if (provider != null) {
      return SelectedHeadlessLiveProvider(
        provider: provider,
        selectionReason: 'selected default provider for $style as fallback',
      );
    }
  }

  return SelectedHeadlessLiveProvider(
    provider: matchingProviders.first,
    selectionReason: 'selected first matching provider for $style as fallback',
  );
}

String? _styleOverrideKey(
  ChatTurnProviderStyle style,
  Map<String, String> environment,
) {
  final key = _styleEnvKey(style);
  final value = environment[key]?.trim();
  return value == null || value.isEmpty ? null : value;
}

String _styleEnvKey(ChatTurnProviderStyle style) {
  switch (style) {
    case ChatTurnProviderStyle.openaiResponses:
      return 'HEADLESS_LIVE_PROVIDER_RESPONSES';
    case ChatTurnProviderStyle.openaiChatCompletions:
      return 'HEADLESS_LIVE_PROVIDER_CHAT_COMPLETIONS';
    case ChatTurnProviderStyle.anthropicMessages:
      return 'HEADLESS_LIVE_PROVIDER_ANTHROPIC';
  }
}

List<String> _preferredProviderIds(ChatTurnProviderStyle style) {
  switch (style) {
    case ChatTurnProviderStyle.openaiResponses:
      return const ['minimax-responses', 'deepseek-responses'];
    case ChatTurnProviderStyle.openaiChatCompletions:
      return const ['minimax-openai', 'deepseek-openai'];
    case ChatTurnProviderStyle.anthropicMessages:
      return const ['deepseek-anthropic', 'minimax-anthropic'];
  }
}

bool _matchesStyle(
  LlmProviderConfig provider,
  ChatTurnProviderStyle style,
  ApiProtocolResolver protocolResolver,
) {
  final apiStyle = protocolResolver.resolveStyle(provider.baseUrl);
  switch (style) {
    case ChatTurnProviderStyle.openaiResponses:
      return apiStyle == ApiStyle.responses;
    case ChatTurnProviderStyle.openaiChatCompletions:
      return apiStyle == ApiStyle.chatCompletions;
    case ChatTurnProviderStyle.anthropicMessages:
      return apiStyle == ApiStyle.anthropicMessages;
  }
}
