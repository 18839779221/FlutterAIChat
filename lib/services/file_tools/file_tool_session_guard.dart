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
    _seenFiles[_normalizeAgentPath(filePath)] = version;
  }

  bool hasSeen(String filePath) =>
      _seenFiles.containsKey(_normalizeAgentPath(filePath));

  FileToolVersionSnapshot? getSeenVersion(String filePath) =>
      _seenFiles[_normalizeAgentPath(filePath)];

  void clearSeen(String filePath) {
    _seenFiles.remove(_normalizeAgentPath(filePath));
  }

  void clearSeenUnder(String pathPrefix) {
    final normalizedPrefix = _normalizeAgentPath(pathPrefix);
    final exactPrefix = normalizedPrefix == '/' ? '/' : '$normalizedPrefix/';
    final matchingKeys = _seenFiles.keys
        .where((key) => key == normalizedPrefix || key.startsWith(exactPrefix))
        .toList(growable: false);
    for (final key in matchingKeys) {
      _seenFiles.remove(key);
    }
  }

  void assertWritable({
    required String filePath,
    required FileToolVersionSnapshot currentVersion,
    required bool fileExists,
  }) {
    if (!fileExists) {
      return;
    }

    final lastSeenVersion = _seenFiles[_normalizeAgentPath(filePath)];
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

  String _normalizeAgentPath(String filePath) {
    final trimmed = filePath.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }
}
