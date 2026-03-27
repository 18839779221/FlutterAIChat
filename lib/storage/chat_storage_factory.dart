import 'package:shared_preferences/shared_preferences.dart';
import 'chat_storage.dart';
import 'chat_storage_factory_stub.dart'
    if (dart.library.io) 'chat_storage_factory_native.dart'
    if (dart.library.html) 'chat_storage_factory_web.dart';

class ChatStorageFactory {
  static ChatStorage create(SharedPreferences preferences) {
    return createChatStorage(preferences);
  }
}
