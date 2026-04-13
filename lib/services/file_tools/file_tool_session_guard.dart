import 'dart:io';

import 'file_tool_models.dart';

class FileToolGuardException implements Exception {
  FileToolGuardException(this.code);

  final String code;

  @override
  String toString() => 'FileToolGuardException($code)';
}

class FileToolSessionGuard {
  final Map<String, FileToolVersionSnapshot> _seenFiles = {};

  void markRead({
    required String filePath,
    required FileToolVersionSnapshot version,
  }) {
    _seenFiles[filePath] = version;
  }

  bool hasSeen(String filePath) => _seenFiles.containsKey(filePath);

  FileToolVersionSnapshot? getSeenVersion(String filePath) =>
      _seenFiles[filePath];

  void assertWritable({
    required String filePath,
    required FileToolVersionSnapshot currentVersion,
    required bool fileExists,
  }) {
    if (!fileExists) {
      return;
    }

    final lastSeenVersion = _seenFiles[filePath];
    if (lastSeenVersion == null) {
      throw FileToolGuardException('unread_file');
    }
    if (lastSeenVersion != currentVersion) {
      throw FileToolGuardException('stale_file_version');
    }
  }

  FileToolVersionSnapshot snapshotForStat(FileStat stat) {
    return FileToolVersionSnapshot(
      modifiedAtMillis: stat.modified.millisecondsSinceEpoch,
      sizeBytes: stat.size,
    );
  }
}
