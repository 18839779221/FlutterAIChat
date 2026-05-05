import 'package:ai_chat/services/debug/debug_turn_inspector_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_dependency_providers.dart';

final debugTurnInspectorPreferencesProvider =
    Provider<DebugTurnInspectorPreferences>((ref) {
  return DebugTurnInspectorPreferences(ref.watch(sharedPreferencesProvider));
});
