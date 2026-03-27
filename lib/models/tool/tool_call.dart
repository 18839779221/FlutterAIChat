import 'dart:convert';

class ToolCall {
  final String toolName;
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.toolName,
    required this.arguments,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    final toolName = json['toolName'];
    final arguments = json['arguments'];

    if (toolName is! String || toolName.trim().isEmpty) {
      throw const FormatException('toolName is required');
    }

    if (arguments != null && arguments is! Map) {
      throw const FormatException('arguments must be a json object');
    }

    return ToolCall(
      toolName: toolName,
      arguments: arguments == null
          ? const {}
          : Map<String, dynamic>.from(arguments as Map<dynamic, dynamic>),
    );
  }

  factory ToolCall.fromRawJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('tool call must be a json object');
    }
    return ToolCall.fromJson(decoded);
  }
}
