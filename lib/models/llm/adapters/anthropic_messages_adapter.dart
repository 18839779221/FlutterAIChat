import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../chat_message.dart';
import '../llm_request_options.dart';
import '../../../services/chat_service.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import 'adapter_utils.dart';
import 'api_style_adapter.dart';

/// Adapter for the Anthropic Messages protocol.
class AnthropicMessagesAdapter extends ApiStyleAdapter {
  const AnthropicMessagesAdapter();

  @override
  ApiStyle get style => ApiStyle.anthropicMessages;

  @override
  Map<String, String> buildHeaders(LLMConfig runtimeConfig) {
    return {
      'Content-Type': 'application/json',
      'x-api-key': runtimeConfig.apiKey,
      'anthropic-version': '2023-06-01',
    };
  }

  @override
  Map<String, dynamic> buildChatPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    return _buildMessagesPayload(
      messages: messages,
      config: config,
      modelName: modelName,
      stream: stream,
      continuationItems: const [],
      requestOptions: requestOptions,
    );
  }

  @override
  Map<String, dynamic> buildPlannerPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
    String? previousResponseId,
    List<Map<String, dynamic>> continuationItems = const [],
    Map<String, dynamic>? providerState,
  }) {
    final normalizedContinuationItems = _normalizeContinuationItems(
      providerState: providerState,
      continuationItems: continuationItems,
    );
    final payload = _buildMessagesPayload(
      messages: messages,
      config: config,
      modelName: modelName,
      stream: false,
      continuationItems: normalizedContinuationItems,
      requestOptions: requestOptions,
    );
    final tools = availableTools
        .map(
          (tool) => {
            'name': tool.name,
            'description': tool.description,
            'input_schema': tool.inputSchema,
          },
        )
        .toList(growable: false);
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      payload['tool_choice'] = {'type': 'auto'};
    }
    return payload;
  }

  @override
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload) {
    final content = payload['content'];
    if (content is! List) {
      return null;
    }
    for (final item in content) {
      if (item is! Map) {
        continue;
      }
      final normalizedItem = item.cast<String, dynamic>();
      if (normalizedItem['type'] == 'tool_use') {
        final toolName = normalizeText(normalizedItem['name']);
        final arguments = decodeToolArguments(normalizedItem['input']);
        if (toolName != null && arguments != null) {
          return PlannerToolChoice.callTool(
            toolName: toolName,
            arguments: arguments,
          );
        }
      }
      final response = extractContentText(normalizedItem);
      if (response != null) {
        return PlannerToolChoice.respond(response);
      }
    }
    return null;
  }

  @override
  String extractNonStreamText(Map<String, dynamic> payload) {
    final content = payload['content'];
    if (content is! List) {
      return '';
    }
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is! Map) {
        continue;
      }
      final text = extractContentText(item.cast<String, dynamic>());
      if (text != null) {
        buffer.write(text);
      }
    }
    return buffer.toString();
  }

  /// Extracts plain text from an Anthropic content block. Public so other
  /// adapters / tests can reuse it.
  static String? extractContentText(Map<String, dynamic> item) {
    final type = item['type'];
    if (type != 'text' && type != 'thinking' && type != 'redacted_thinking') {
      return null;
    }
    final text = normalizeText(item['text'] ?? item['thinking']);
    return text;
  }

  Map<String, dynamic> _buildMessagesPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    required List<Map<String, dynamic>> continuationItems,
    required LlmRequestOptions requestOptions,
  }) {
    final systemSegments = <String>[];
    final configuredSystemPrompt = config.systemPrompt.trim();
    if (configuredSystemPrompt.isNotEmpty) {
      systemSegments.add(configuredSystemPrompt);
    }

    final normalizedMessages = <Map<String, dynamic>>[];
    for (final message in messages) {
      final trimmedText = message.text.trim();
      if (trimmedText.isEmpty) {
        continue;
      }
      if (message.role == MessageRole.system) {
        systemSegments.add(trimmedText);
        continue;
      }
      normalizedMessages.add(
        _buildMessage(message),
      );
    }

    if (continuationItems.isNotEmpty) {
      normalizedMessages.addAll(
        continuationItems.map((item) => Map<String, dynamic>.from(item)),
      );
    }

    return {
      'model': modelName,
      if (systemSegments.isNotEmpty) 'system': systemSegments.join('\n\n'),
      'messages': normalizedMessages,
      'stream': stream,
      if (requestOptions.maxOutputTokens != null)
        'max_tokens': requestOptions.maxOutputTokens,
      if (!requestOptions.allowReasoning)
        'thinking': const {'type': 'disabled'},
    };
  }

  Map<String, dynamic> _buildMessage(ChatMessage message) {
    final contextType = modelContextTypeOf(message);
    if (contextType == assistantToolUseContextType) {
      final providerCallId = providerCallIdOf(message);
      final toolName = toolNameOf(message);
      if (toolName != null && providerCallId != null) {
        return {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': providerCallId,
              'name': toolName,
              'input': toolArgumentsOf(message) ?? const {},
            },
          ],
        };
      }
    }
    if (contextType == userToolResultContextType) {
      final providerCallId = providerCallIdOf(message);
      if (providerCallId != null) {
        return {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': providerCallId,
              'content': message.text,
            },
          ],
        };
      }
    }
    return {
      'role': message.role == MessageRole.assistant ? 'assistant' : 'user',
      'content': [
        {
          'type': 'text',
          'text': message.text,
        },
      ],
    };
  }

  List<Map<String, dynamic>> _normalizeContinuationItems({
    required Map<String, dynamic>? providerState,
    required List<Map<String, dynamic>> continuationItems,
  }) {
    if (continuationItems.isEmpty) {
      return continuationItems;
    }

    final hasAssistantContinuation = continuationItems.any((item) {
      if (item['role'] != 'assistant') {
        return false;
      }
      final content = item['content'];
      return content is List && content.isNotEmpty;
    });
    if (hasAssistantContinuation) {
      return continuationItems;
    }

    final contentBlocks = providerState?['content_blocks'];
    if (contentBlocks is! List) {
      return continuationItems;
    }
    final normalizedBlocks = contentBlocks
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    if (normalizedBlocks.isEmpty) {
      return continuationItems;
    }

    return [
      {
        'role': 'assistant',
        'content': normalizedBlocks,
      },
      ...continuationItems,
    ];
  }
}
