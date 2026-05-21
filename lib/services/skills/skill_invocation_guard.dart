import '../../models/chat_event.dart';

/// Detects whether a skill has already been successfully invoked in a turn.
class SkillInvocationGuard {
  const SkillInvocationGuard();

  bool wasSkillInvoked({
    required List<ChatEvent> events,
    required String skillId,
    required String skillName,
  }) {
    final normalizedId = _normalizeLookupKey(skillId);
    final normalizedName = _normalizeLookupKey(skillName);
    for (final event in events) {
      if (event.eventType != ChatEventType.toolResult) {
        continue;
      }
      final payload = event.payloadJson;
      if (payload == null || payload['toolName']?.toString().trim() != 'skill') {
        continue;
      }
      if (payload['status']?.toString().trim() != 'success') {
        continue;
      }
      final rawData = payload['data'];
      if (rawData is! Map) {
        continue;
      }
      final data = Map<String, dynamic>.from(rawData);
      final existingId = _normalizeLookupKey(
        data['skillId']?.toString().trim() ?? '',
      );
      if (existingId.isNotEmpty && existingId == normalizedId) {
        return true;
      }
      final existingName = _normalizeLookupKey(
        data['name']?.toString().trim() ?? '',
      );
      if (existingName.isNotEmpty &&
          (existingName == normalizedName || existingName == normalizedId)) {
        return true;
      }
    }
    return false;
  }

  String _normalizeLookupKey(String value) {
    final lower = value.trim().toLowerCase();
    final normalized = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return normalized.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }
}
