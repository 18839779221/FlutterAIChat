import 'package:shared_preferences/shared_preferences.dart';
import 'chat_storage.dart';
import '../database/database_helper.dart';

ChatStorage createChatStorage(SharedPreferences preferences) {
  return DatabaseHelper();
}
