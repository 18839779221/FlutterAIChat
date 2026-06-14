import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/chat/chat_attachment.dart';
import '../default_tool_adapters.dart';
import 'chat_attachment_host_file_resolver.dart';

const MethodChannel _hostToolsChannel = MethodChannel('ai_chat/host_tools');

typedef AttachmentHostIntentLauncher = Future<HostIntentResult> Function(
  HostIntentRequest request,
);

class AttachmentGallerySaveResult {
  const AttachmentGallerySaveResult({
    required this.isSuccess,
    required this.message,
    this.errorCode,
  });

  final bool isSuccess;
  final String message;
  final String? errorCode;
}

/// Saves an attachment image into the Android system gallery through the host bridge.
class ChatAttachmentGallerySaveService {
  ChatAttachmentGallerySaveService({
    required ChatAttachmentHostFileResolver hostFileResolver,
    AttachmentHostIntentLauncher? launchIntent,
    TargetPlatform? platformOverride,
  })  : _hostFileResolver = hostFileResolver,
        _launchIntent = launchIntent ?? _defaultGalleryHostIntentLauncher,
        _platformOverride = platformOverride;

  final ChatAttachmentHostFileResolver _hostFileResolver;
  final AttachmentHostIntentLauncher _launchIntent;
  final TargetPlatform? _platformOverride;

  Future<AttachmentGallerySaveResult> saveToGallery(
    ChatAttachment attachment,
  ) async {
    final platform = _platformOverride ?? defaultTargetPlatform;
    if (platform != TargetPlatform.android) {
      return const AttachmentGallerySaveResult(
        isSuccess: false,
        message: '当前平台暂不支持保存到系统相册',
        errorCode: 'unsupported_platform',
      );
    }

    final sourceFile = _hostFileResolver.resolve(attachment.localPath);
    if (sourceFile == null || !sourceFile.existsSync()) {
      return const AttachmentGallerySaveResult(
        isSuccess: false,
        message: '图片文件不存在，无法保存到系统相册',
        errorCode: 'missing_file',
      );
    }

    final result = await _launchIntent(
      HostIntentRequest(
        action: 'save_image_to_gallery',
        arguments: {
          'sourcePath': sourceFile.path,
          'fileName': attachment.fileName,
          'mimeType': attachment.mimeType,
        },
      ),
    );

    if (result.status == HostIntentStatus.launched) {
      return const AttachmentGallerySaveResult(
        isSuccess: true,
        message: '已保存到系统相册',
      );
    }

    if (result.status == HostIntentStatus.unavailable) {
      return AttachmentGallerySaveResult(
        isSuccess: false,
        message: '系统相册不可用，保存失败',
        errorCode: result.message ?? 'gallery_unavailable',
      );
    }

    return AttachmentGallerySaveResult(
      isSuccess: false,
      message: '保存到系统相册失败',
      errorCode: result.message ?? 'gallery_save_failed',
    );
  }
}

Future<HostIntentResult> _defaultGalleryHostIntentLauncher(
  HostIntentRequest request,
) async {
  try {
    final response = await _hostToolsChannel.invokeMapMethod<String, dynamic>(
      'launchHostIntent',
      {
        'action': request.action,
        'arguments': request.arguments,
      },
    );
    final rawStatus = response?['status'] as String?;
    final status = HostIntentStatus.values.firstWhere(
      (value) => value.name == rawStatus,
      orElse: () => HostIntentStatus.failed,
    );
    return HostIntentResult(
      status: status,
      message: response?['message'] as String?,
    );
  } catch (_) {
    return const HostIntentResult(
      status: HostIntentStatus.failed,
      message: 'intent_failed',
    );
  }
}
