import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';

import 'headless_live_provider_matrix.dart';

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

/// Describes observed live-test behavior for one concrete upstream provider.
///
/// This stays in the test layer so provider-specific quirks do not leak into
/// production orchestration contracts.
enum StructuredCheckpointExpectation {
  /// The provider is expected to stably emit the structured checkpoint.
  required,

  /// The provider may emit the structured checkpoint, but real traffic has
  /// shown fallback to plain assistant text / inline completion is possible.
  opportunistic,
}

class HeadlessLiveProviderProfile {
  const HeadlessLiveProviderProfile({
    required this.askUserInteraction,
    required this.toolConfirmation,
    required this.multiToolContinuation,
  });

  /// Live expectation for the structured `ask_user_question` checkpoint.
  final StructuredCheckpointExpectation askUserInteraction;

  /// Live expectation for the shared write-confirmation checkpoint.
  final StructuredCheckpointExpectation toolConfirmation;

  /// Live expectation for whether the provider stably continues with multiple
  /// sequential tool decisions instead of collapsing to one tool or one final
  /// answer in the same scenario.
  final StructuredCheckpointExpectation multiToolContinuation;
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
  final defaults = LlmLocalDefaults.fromJson(Map<String, dynamic>.from(decoded));
  return _augmentWithCodexResponsesProvider(defaults);
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
    final normalizedOverrideId = _normalizeProviderOverrideId(overrideId);
    final provider = defaults.providers
        .where((item) => item.id == normalizedOverrideId)
        .firstOrNull;
    if (provider == null) {
      throw StateError(
        'Injected provider "$overrideId" from ${_styleEnvKey(style)} was not found in local defaults.',
      );
    }
    return SelectedHeadlessLiveProvider(
      provider: provider,
      selectionReason:
          normalizedOverrideId == overrideId
              ? 'selected from ${_styleEnvKey(style)} override'
              : 'selected from ${_styleEnvKey(style)} override alias=$overrideId',
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

String _normalizeProviderOverrideId(String providerId) {
  switch (providerId) {
    case 'minimax-openai':
      return 'minimax-openai-chat-completions';
    case 'deepseek-openai':
      return 'deepseek-openai-chat-completions';
    default:
      return providerId;
  }
}

LlmLocalDefaults _augmentWithCodexResponsesProvider(LlmLocalDefaults defaults) {
  final fallbackProvider = _loadCodexResponsesProvider();
  if (fallbackProvider == null) {
    return defaults;
  }

  final providers = <LlmProviderConfig>[
    fallbackProvider,
    ...defaults.providers.where((item) => item.id != fallbackProvider.id),
  ];
  final defaultProviderId = switch (defaults.defaultProviderId) {
    'beehears-responses' => fallbackProvider.id,
    final value => value,
  };

  return LlmLocalDefaults(
    defaultProviderId: defaultProviderId,
    defaultModelId: defaults.defaultModelId,
    providers: providers,
    additionalConfig: defaults.additionalConfig,
    speechInput: defaults.speechInput,
  );
}

LlmProviderConfig? _loadCodexResponsesProvider() {
  try {
    final configFile = File('/Users/zyb_wl/.codex/config.toml');
    final authFile = File('/Users/zyb_wl/.codex/auth.json');
    if (!configFile.existsSync() || !authFile.existsSync()) {
      return null;
    }

    final configText = configFile.readAsStringSync();
    if (!_tomlContainsResponsesCustomProvider(configText)) {
      return null;
    }

    final baseUrl = _extractTomlString(
      configText,
      section: 'model_providers.custom',
      key: 'base_url',
    );
    final modelId = _extractTomlString(configText, key: 'model');
    if (baseUrl == null || modelId == null) {
      return null;
    }

    final authJson = jsonDecode(authFile.readAsStringSync());
    if (authJson is! Map) {
      return null;
    }
    final apiKey = (authJson['OPENAI_API_KEY'] as String?)?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      return null;
    }

    return LlmProviderConfig(
      id: 'codex-custom-responses',
      name: 'Codex Custom Responses',
      apiKey: apiKey,
      baseUrl: '$baseUrl/responses',
      models: <LlmProviderModel>[
        LlmProviderModel(id: modelId, name: modelId),
      ],
    );
  } catch (_) {
    return null;
  }
}

bool _tomlContainsResponsesCustomProvider(String configText) {
  return configText.contains('[model_providers.custom]') &&
      configText.contains('wire_api = "responses"');
}

String? _extractTomlString(
  String configText, {
  String? section,
  required String key,
}) {
  final lines = const LineSplitter().convert(configText);
  var inSection = section == null;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      inSection = section != null && trimmed == '[$section]';
      continue;
    }
    if (!inSection || !trimmed.startsWith('$key = ')) {
      continue;
    }
    final separatorIndex = trimmed.indexOf('=');
    if (separatorIndex == -1) {
      continue;
    }
    final rawValue = trimmed.substring(separatorIndex + 1).trim();
    if (!rawValue.startsWith('"') || !rawValue.endsWith('"')) {
      continue;
    }
    final value = rawValue.substring(1, rawValue.length - 1).trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

HeadlessLiveProviderProfile resolveHeadlessLiveProviderProfile(
  String providerId,
) {
  return headlessLiveProviderMatrix[providerId] ??
      const HeadlessLiveProviderProfile(
        askUserInteraction: StructuredCheckpointExpectation.required,
        toolConfirmation: StructuredCheckpointExpectation.required,
        multiToolContinuation: StructuredCheckpointExpectation.required,
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
      return const [
        'codex-custom-responses',
        'beehears-responses',
        'minimax-responses',
        'deepseek-responses',
      ];
    case ChatTurnProviderStyle.openaiChatCompletions:
      return const [
        'minimax-openai-chat-completions',
        'deepseek-openai-chat-completions',
        'minimax-openai',
        'deepseek-openai',
      ];
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
