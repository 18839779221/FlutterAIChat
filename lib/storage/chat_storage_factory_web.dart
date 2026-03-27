import 'package:shared_preferences/shared_preferences.dart';
import 'chat_storage.dart';
import 'web_chat_storage.dart';

ChatStorage createChatStorage(SharedPreferences preferences) {
  return WebChatStorage(preferences);
}
