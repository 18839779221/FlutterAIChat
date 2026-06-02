import 'file_tool_models.dart';
import 'file_tool_post_write_hook.dart';
import 'file_tool_root_service.dart';
import 'file_tool_session_guard.dart';

const int _contentPreviewMaxChars = 12000;

class FileToolWriteException implements Exception {
  FileToolWriteException(this.code);

  final String code;

  @override
  String toString() => 'FileToolWriteException($code)';
}

class FileToolWriteOutcome {
  /// Agent path that was created, overwritten, or edited.
  final String filePath;

  /// Whether the target existed before this write transaction.
  final bool filePreviouslyExisted;

  /// File version snapshot after the write transaction completed.
  final FileToolVersionSnapshot version;

  /// Character count before the mutation. New files report zero.
  final int oldLength;

  /// Character count after the mutation.
  final int newLength;

  /// Number of replacements performed by Edit. Write reports zero.
  final int replacementCount;

  /// Lightweight old-content preview used by the UI to render change review.
  final String oldContentPreview;

  /// Lightweight new-content preview used by the UI to render change review.
  final String newContentPreview;

  /// Whether either preview was shortened before being persisted to payloads.
  final bool contentPreviewTruncated;

  /// Tool-host metadata produced after the write, such as format results.
  final Map<String, dynamic> postWriteData;

  const FileToolWriteOutcome({
    required this.filePath,
    required this.filePreviouslyExisted,
    required this.version,
    required this.oldLength,
    required this.newLength,
    required this.replacementCount,
    required this.oldContentPreview,
    required this.newContentPreview,
    required this.contentPreviewTruncated,
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
      'oldContentPreview': oldContentPreview,
      'newContentPreview': newContentPreview,
      'contentPreviewTruncated': contentPreviewTruncated,
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
    final agentPath = _normalizeAgentPath(relativePath);
    final file = _rootService.resolveFile(_relativePathFromAgentPath(agentPath));
    final fileExists = file.existsSync();
    String? oldContent;
    if (fileExists) {
      oldContent = await file.readAsString();
      _sessionGuard.assertWritable(
        filePath: agentPath,
        currentVersion: _sessionGuard.snapshotForStat(await file.stat()),
        fileExists: true,
      );
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    final version = _sessionGuard.snapshotForStat(await file.stat());
    _sessionGuard.markRead(filePath: agentPath, version: version);
    final postWriteData = await _postWriteHook.afterWrite(
      FileToolPostWriteContext(
        filePath: agentPath,
        oldContent: oldContent,
        newContent: content,
      ),
    );
    return FileToolWriteOutcome(
      filePath: agentPath,
      filePreviouslyExisted: fileExists,
      version: version,
      oldLength: oldContent?.length ?? 0,
      newLength: content.length,
      replacementCount: 0,
      oldContentPreview: _previewContent(oldContent ?? ''),
      newContentPreview: _previewContent(content),
      contentPreviewTruncated:
          _isPreviewTruncated(oldContent ?? '') || _isPreviewTruncated(content),
      postWriteData: postWriteData,
    );
  }

  Future<FileToolWriteOutcome> editFile({
    required String relativePath,
    required String oldString,
    required String newString,
    required bool replaceAll,
  }) async {
    final agentPath = _normalizeAgentPath(relativePath);
    final file = _rootService.resolveFile(_relativePathFromAgentPath(agentPath));
    if (!file.existsSync()) {
      throw FileToolWriteException('file_not_found');
    }

    final currentVersion = _sessionGuard.snapshotForStat(await file.stat());
    _sessionGuard.assertWritable(
      filePath: agentPath,
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
    _sessionGuard.markRead(filePath: agentPath, version: nextVersion);
    final postWriteData = await _postWriteHook.afterWrite(
      FileToolPostWriteContext(
        filePath: agentPath,
        oldContent: originalContent,
        newContent: nextContent,
      ),
    );
    return FileToolWriteOutcome(
      filePath: agentPath,
      filePreviouslyExisted: true,
      version: nextVersion,
      oldLength: originalContent.length,
      newLength: nextContent.length,
      replacementCount: replaceAll ? matchCount : 1,
      oldContentPreview: _previewContent(originalContent),
      newContentPreview: _previewContent(nextContent),
      contentPreviewTruncated: _isPreviewTruncated(originalContent) ||
          _isPreviewTruncated(nextContent),
      postWriteData: postWriteData,
    );
  }

  String _previewContent(String content) {
    if (!_isPreviewTruncated(content)) {
      return content;
    }
    return content.substring(0, _contentPreviewMaxChars);
  }

  bool _isPreviewTruncated(String content) {
    return content.length > _contentPreviewMaxChars;
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

  String _normalizeAgentPath(String pathValue) {
    final trimmed = pathValue.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) {
      return '/';
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  String _relativePathFromAgentPath(String agentPath) {
    if (agentPath == '/') {
      return '';
    }
    return agentPath.substring(1);
  }
}
