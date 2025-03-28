class Logger {
  static void d(String tag, String message) {
    print('💙 DEBUG [$tag] $message');
  }

  static void i(String tag, String message) {
    print('💚 INFO [$tag] $message');
  }

  static void w(String tag, String message) {
    print('💛 WARN [$tag] $message');
  }

  static void e(String tag, String message, [dynamic error]) {
    print('❤️ ERROR [$tag] $message');
    if (error != null) {
      print('❤️ ERROR [$tag] Stack trace: $error');
    }
  }
} 