import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'log_file_sink_base.dart';

class NativeLogFileSink implements LogFileSink {
  NativeLogFileSink({
    required this.file,
  });

  final File file;
  Future<void> _pending = Future<void>.value();

  @override
  String get filePath => file.path;

  @override
  Future<void> writeLine(String line) {
    _pending = _pending.then((_) async {
      await file.writeAsString(
        '$line\n',
        mode: FileMode.append,
        flush: true,
      );
    });
    return _pending;
  }
}

Future<LogFileSink?> createPlatformLogFileSink() async {
  final appSupportDirectory = await getApplicationSupportDirectory();
  final logsDirectory = Directory(path.join(appSupportDirectory.path, 'logs'));
  await logsDirectory.create(recursive: true);
  final file = File(path.join(logsDirectory.path, 'app.log'));
  if (!await file.exists()) {
    await file.create(recursive: true);
  }
  return NativeLogFileSink(file: file);
}
