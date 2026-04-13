import 'file_tool_models.dart';
import 'file_tool_post_write_hook.dart';
import 'file_tool_root_service.dart';
import 'file_tool_session_guard.dart';

class FileToolWriteException implements Exception {
  FileToolWriteException(this.code);

  final String code;

  @override
  String toString() => 'FileToolWriteException($code)';
}

class FileToolWriteOutcome {
  final String filePath;
  final bool filePreviouslyExisted;
  final FileToolVersionSnapshot version;
  final int oldLength;
  final int newLength;
  final int replacementCount;
  final Map<String, dynamic> postWriteData;

  const FileToolWriteOutcome({
    required this.filePath,
    required this.filePreviouslyExisted,
    required this.version,
    required this.oldLength,
    required this.newLength,
    required this.replacementCount,
    required this.postWriteData,
  });

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'filePreviouslyExisted': filePreviouslyExisted,
      'fileVersion': version.toJson(),
      'oldLength': oldLength,
      'newLength': newLength,
      'replacementCount': replacementCount,
      'postWriteData': postWriteData,
    };
  }
}

class FileToolWriteService {
  FileToolWriteService({
    required FileToolRootService rootService,
    required FileToolSessionGuard sessionGuard,
    FileToolPostWriteHook postWriteHook = const NoopFileToolPostWriteHook(),
  })  : _rootService = rootService,
        _sessionGuard = sessionGuard,
        _postWriteHook = postWriteHook;

  final FileToolRootService _rootService;
  final FileToolSessionGuard _sessionGuard;
  final FileToolPostWriteHook _postWriteHook;

  Future<FileToolWriteOutcome> writeFile({
    required String relativePath,
    required String content,
  }) async {
    final file = _rootService.resolveFile(relativePath);
    final fileExists = file.existsSync();
    String? oldContent;
    if (fileExists) {
      oldContent = await file.readAsString();
      _sessionGuard.assertWritable(
        filePath: relativePath,
        currentVersion: _sessionGuard.snapshotForStat(await file.stat()),
        fileExists: true,
      );
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    final version = _sessionGuard.snapshotForStat(await file.stat());
    _sessionGuard.markRead(filePath: relativePath, version: version);
    final postWriteData = await _postWriteHook.afterWrite(
      FileToolPostWriteContext(
        filePath: relativePath,
        oldContent: oldContent,
        newContent: content,
      ),
    );
    return FileToolWriteOutcome(
      filePath: relativePath,
      filePreviouslyExisted: fileExists,
      version: version,
      oldLength: oldContent?.length ?? 0,
      newLength: content.length,
      replacementCount: 0,
      postWriteData: postWriteData,
    );
  }

  Future<FileToolWriteOutcome> editFile({
    required String relativePath,
    required String oldString,
    required String newString,
    required bool replaceAll,
  }) async {
    final file = _rootService.resolveFile(relativePath);
    if (!file.existsSync()) {
      throw FileToolWriteException('file_not_found');
    }

    final currentVersion = _sessionGuard.snapshotForStat(await file.stat());
    _sessionGuard.assertWritable(
      filePath: relativePath,
      currentVersion: currentVersion,
      fileExists: true,
    );

    final originalContent = await file.readAsString();
    final matchCount = _countOccurrences(originalContent, oldString);
    if (matchCount == 0) {
      throw FileToolWriteException('old_string_not_found');
    }
    if (matchCount > 1 && !replaceAll) {
      throw FileToolWriteException('ambiguous_old_string');
    }

    final nextContent = replaceAll
        ? originalContent.replaceAll(oldString, newString)
        : originalContent.replaceFirst(oldString, newString);
    await file.writeAsString(nextContent);
    final nextVersion = _sessionGuard.snapshotForStat(await file.stat());
    _sessionGuard.markRead(filePath: relativePath, version: nextVersion);
    final postWriteData = await _postWriteHook.afterWrite(
      FileToolPostWriteContext(
        filePath: relativePath,
        oldContent: originalContent,
        newContent: nextContent,
      ),
    );
    return FileToolWriteOutcome(
      filePath: relativePath,
      filePreviouslyExisted: true,
      version: nextVersion,
      oldLength: originalContent.length,
      newLength: nextContent.length,
      replacementCount: replaceAll ? matchCount : 1,
      postWriteData: postWriteData,
    );
  }

  int _countOccurrences(String text, String pattern) {
    if (pattern.isEmpty) {
      return 0;
    }
    var count = 0;
    var cursor = 0;
    while (true) {
      final nextIndex = text.indexOf(pattern, cursor);
      if (nextIndex == -1) {
        return count;
      }
      count += 1;
      cursor = nextIndex + pattern.length;
    }
  }
}
