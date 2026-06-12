import '../chat_turn.dart';

enum SessionRuntimeSlot {
  primary,
  side,
}

class SessionRuntimeConfig {
  final int? id;
  final int groupId;
  final String providerId;
  final String modelId;
  final ChatTurnProviderStyle providerStyle;
  final String? sideProviderId;
  final String? sideModelId;
  final ChatTurnProviderStyle? sideProviderStyle;
  final DateTime updatedAt;

  SessionRuntimeConfig({
    this.id,
    required this.groupId,
    required this.providerId,
    required this.modelId,
    required this.providerStyle,
    this.sideProviderId,
    this.sideModelId,
    this.sideProviderStyle,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'group_id': groupId,
      'provider_id': providerId,
      'model_id': modelId,
      'provider_style': providerStyle.name,
      'side_provider_id': sideProviderId,
      'side_model_id': sideModelId,
      'side_provider_style': sideProviderStyle?.name,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory SessionRuntimeConfig.fromMap(Map<String, dynamic> map) {
    return SessionRuntimeConfig(
      id: map['id'] as int?,
      groupId: map['group_id'] as int,
      providerId: map['provider_id'] as String? ?? '',
      modelId: map['model_id'] as String? ?? '',
      providerStyle: ChatTurnProviderStyle.values.firstWhere(
        (item) => item.name == map['provider_style'],
        orElse: () => ChatTurnProviderStyle.openaiChatCompletions,
      ),
      sideProviderId: _normalizeOptional(map['side_provider_id']),
      sideModelId: _normalizeOptional(map['side_model_id']),
      sideProviderStyle: _readProviderStyle(map['side_provider_style']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  SessionRuntimeConfig copyWith({
    int? id,
    int? groupId,
    String? providerId,
    String? modelId,
    ChatTurnProviderStyle? providerStyle,
    String? sideProviderId,
    String? sideModelId,
    ChatTurnProviderStyle? sideProviderStyle,
    bool clearSideProviderId = false,
    bool clearSideModelId = false,
    bool clearSideProviderStyle = false,
    DateTime? updatedAt,
  }) {
    return SessionRuntimeConfig(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      providerStyle: providerStyle ?? this.providerStyle,
      sideProviderId:
          clearSideProviderId ? null : sideProviderId ?? this.sideProviderId,
      sideModelId: clearSideModelId ? null : sideModelId ?? this.sideModelId,
      sideProviderStyle: clearSideProviderStyle
          ? null
          : sideProviderStyle ?? this.sideProviderStyle,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String providerIdForSlot(SessionRuntimeSlot slot) {
    if (slot == SessionRuntimeSlot.side) {
      return _normalizeOptional(sideProviderId) ?? providerId;
    }
    return providerId;
  }

  String modelIdForSlot(SessionRuntimeSlot slot) {
    if (slot == SessionRuntimeSlot.side) {
      return _normalizeOptional(sideModelId) ?? modelId;
    }
    return modelId;
  }

  ChatTurnProviderStyle providerStyleForSlot(SessionRuntimeSlot slot) {
    if (slot == SessionRuntimeSlot.side) {
      return sideProviderStyle ?? providerStyle;
    }
    return providerStyle;
  }

  static String? _normalizeOptional(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static ChatTurnProviderStyle? _readProviderStyle(dynamic value) {
    final normalized = _normalizeOptional(value);
    if (normalized == null) {
      return null;
    }
    return ChatTurnProviderStyle.values.firstWhere(
      (item) => item.name == normalized,
      orElse: () => ChatTurnProviderStyle.openaiChatCompletions,
    );
  }
}
