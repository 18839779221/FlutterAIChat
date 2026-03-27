import 'package:shared_preferences/shared_preferences.dart';
import 'chat_storage.dart';

ChatStorage createChatStorage(SharedPreferences preferences) {
  throw UnsupportedError('当前平台不支持 ChatStorage');
}
