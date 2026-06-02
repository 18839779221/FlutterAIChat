import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/chat/chat_attachment.dart';
import '../../utils/logger.dart';
import '../workspace/workspace_binding_service.dart';

typedef AttachmentRootDirectoryResolver = Future<Directory> Function();
typedef AttachmentWorkspaceIdResolver = Future<String?> Function();

/// Persists selected images into app-managed storage.
class ChatAttachmentStorageService {
  ChatAttachmentStorageService({
    required AttachmentRootDirectoryResolver resolveRootDirectory,
    AttachmentWorkspaceIdResolver? resolveWorkspaceId,
    WorkspaceBindingService? workspaceBindingService,
  })  : _resolveRootDirectory = resolveRootDirectory,
        _resolveWorkspaceId = resolveWorkspaceId ?? _defaultWorkspaceIdResolver,
        _workspaceBindingService =
            workspaceBindingService ?? WorkspaceBindingService();

  final AttachmentRootDirectoryResolver _resolveRootDirectory;
  final AttachmentWorkspaceIdResolver _resolveWorkspaceId;
  final WorkspaceBindingService _workspaceBindingService;

  Future<ChatAttachment> persistSelectedImage({
    required ChatAttachment attachment,
  }) async {
    Logger.runtime(
      'ChatAttachmentStorageService',
      'persistSelectedImage started',
      data: {
        'localId': attachment.localId,
        'fileName': attachment.fileName,
        'sourcePath': attachment.localPath,
      },
    );
    final sourcePath = attachment.localPath;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      throw ArgumentError('attachment.localPath is required');
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      Logger.w(
        'ChatAttachmentStorageService',
        'source image missing before persist: $sourcePath',
      );
      throw FileSystemException('Source image does not exist', sourcePath);
    }

    final root = await _resolveRootDirectory();
    final resolvedWorkspace = _workspaceBindingService.resolveWorkspaceId(
      await _resolveWorkspaceId(),
    );
    final persistedDir = Directory(
      p.join(
        root.path,
        'workspaces',
        resolvedWorkspace.workspaceId,
        'attachments',
        'persisted',
      ),
    );
    final thumbsDir = Directory(
      p.join(
        root.path,
        'workspaces',
        resolvedWorkspace.workspaceId,
        'attachments',
        'thumbs',
      ),
    );
    await persistedDir.create(recursive: true);
    await thumbsDir.create(recursive: true);

    final storedFileName = '${attachment.localId}_${attachment.fileName}';
    final persistedPath = p.join(persistedDir.path, storedFileName);
    await sourceFile.copy(persistedPath);
    final bytes = await sourceFile.readAsBytes();
    final dataUrl =
        'data:${attachment.mimeType};base64,${base64Encode(bytes)}';
    Logger.runtime(
      'ChatAttachmentStorageService',
      'persistSelectedImage completed',
      data: {
        'localId': attachment.localId,
        'persistedPath': persistedPath,
        'byteCount': bytes.length,
        'dataUrlLength': dataUrl.length,
      },
    );

    return attachment.copyWith(
      localPath: _agentPathFor(
        'workspaces/${resolvedWorkspace.workspaceId}/attachments/persisted/$storedFileName',
      ),
      thumbnailPath: _agentPathFor(
        'workspaces/${resolvedWorkspace.workspaceId}/attachments/thumbs/$storedFileName',
      ),
      status: ChatAttachmentStatus.ready,
      providerFileRefJson: {
        ...?attachment.providerFileRefJson,
        'data_url': dataUrl,
        'data_url_length': dataUrl.length,
        'send_mime_type': attachment.mimeType,
      },
      updatedAt: DateTime.now(),
    );
  }

  String _agentPathFor(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }

  static Future<String?> _defaultWorkspaceIdResolver() async {
    return null;
  }
}
