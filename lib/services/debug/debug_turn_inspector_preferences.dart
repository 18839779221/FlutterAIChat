import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight UI preferences for the debug turn inspector.
class DebugTurnInspectorPreferences {
  static const String _lastTabIndexKey = 'debug.turn_inspector.last_tab_index';

  DebugTurnInspectorPreferences(this._preferences);

  final SharedPreferences _preferences;

  int getLastTabIndex() {
    return _preferences.getInt(_lastTabIndexKey) ?? 0;
  }

  Future<void> setLastTabIndex(int index) async {
    await _preferences.setInt(_lastTabIndexKey, index);
  }
}
