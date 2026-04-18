import 'log_file_sink_base.dart';
import 'log_file_sink_stub.dart'
    if (dart.library.io) 'log_file_sink_native.dart';

Future<LogFileSink?> createLogFileSink() {
  return createPlatformLogFileSink();
}
