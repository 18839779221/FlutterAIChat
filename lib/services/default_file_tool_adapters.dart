import 'file_tools/file_tool_host_adapters.dart';
import 'default_file_tool_adapters_stub.dart'
    if (dart.library.io) 'default_file_tool_adapters_native.dart';

Future<FileToolHostAdapters?> buildDefaultFileToolHostAdapters() {
  return buildPlatformFileToolHostAdapters();
}
