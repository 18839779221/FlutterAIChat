import 'dart:io';

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

  /// Deleted target type for Delete operations. Null for Write/Edit.
  final String? deletedType;

  /// Number of files removed by Delete. Zero for Write/Edit.
  final int deletedFileCount;

  /// Number of directories removed by Delete. Zero for Write/Edit.
  final int deletedDirectoryCount;

  /// Whether the deleted target contained child entries. False for Write/Edit.
  final bool hadChildren;

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
    this.deletedType,
    this.deletedFileCount = 0,
    this.deletedDirectoryCount = 0,
    this.hadChildren = false,
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
      if (deletedType != null) 'deletedType': deletedType,
      'deletedFileCount': deletedFileCount,
      'deletedDirectoryCount': deletedDirectoryCount,
      'hadChildren': hadChildren,
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
    final file =
        _rootService.resolveFile(_relativePathFromAgentPath(agentPath));
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
    final file =
        _rootService.resolveFile(_relativePathFromAgentPath(agentPath));
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

  Future<FileToolWriteOutcome> deletePath({
    required String relativePath,
  }) async {
    final agentPath = _normalizeAgentPath(relativePath);
    final fileSystemEntity = _rootService.resolveFile(
      _relativePathFromAgentPath(agentPath),
    );
    final entityType = FileSystemEntity.typeSync(
      fileSystemEntity.path,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.notFound) {
      throw FileToolWriteException('file_not_found');
    }

    if (entityType == FileSystemEntityType.file) {
      final file = File(fileSystemEntity.path);
      final originalContent = await file.readAsString();
      await file.delete();
      _sessionGuard.clearSeen(agentPath);
      return FileToolWriteOutcome(
        filePath: agentPath,
        filePreviouslyExisted: true,
        version: const FileToolVersionSnapshot(
          modifiedAtMillis: 0,
          sizeBytes: 0,
        ),
        oldLength: originalContent.length,
        newLength: 0,
        replacementCount: 0,
        oldContentPreview: _previewContent(originalContent),
        newContentPreview: '',
        contentPreviewTruncated: _isPreviewTruncated(originalContent),
        postWriteData: const {},
        deletedType: 'file',
        deletedFileCount: 1,
        deletedDirectoryCount: 0,
        hadChildren: false,
      );
    }

    final directory = Directory(fileSystemEntity.path);
    final children = directory.listSync(recursive: true, followLinks: false);
    var deletedFileCount = 0;
    var deletedDirectoryCount = 1;
    for (final child in children) {
      if (child is File) {
        deletedFileCount += 1;
      } else if (child is Directory) {
        deletedDirectoryCount += 1;
      }
    }
    await directory.delete(recursive: true);
    _sessionGuard.clearSeenUnder(agentPath);
    return FileToolWriteOutcome(
      filePath: agentPath,
      filePreviouslyExisted: true,
      version: const FileToolVersionSnapshot(
        modifiedAtMillis: 0,
        sizeBytes: 0,
      ),
      oldLength: 0,
      newLength: 0,
      replacementCount: 0,
      oldContentPreview: '',
      newContentPreview: '',
      contentPreviewTruncated: false,
      postWriteData: const {},
      deletedType: 'directory',
      deletedFileCount: deletedFileCount,
      deletedDirectoryCount: deletedDirectoryCount,
      hadChildren: children.isNotEmpty,
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
