import 'dart:convert';

enum ChatAttachmentKind { image }

enum ChatAttachmentSource { localFile, providerFile, remoteUrl }

enum ChatAttachmentStatus { selected, preparing, uploading, ready, failed }

/// User-provided attachment associated with a chat message.
class ChatAttachment {
  ChatAttachment({
    required this.localId,
    required this.kind,
    required this.source,
    required this.fileName,
    required this.mimeType,
    required this.status,
    this.byteSize,
    this.localPath,
    this.thumbnailPath,
    this.sha256,
    this.errorCode,
    this.errorMessage,
    this.providerFileRefJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ChatAttachment.image({
    required String localId,
    required String fileName,
    required String mimeType,
    required ChatAttachmentStatus status,
    int? byteSize,
    String? localPath,
    String? thumbnailPath,
    String? sha256,
    String? errorCode,
    String? errorMessage,
    Map<String, dynamic>? providerFileRefJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatAttachment(
      localId: localId,
      kind: ChatAttachmentKind.image,
      source: ChatAttachmentSource.localFile,
      fileName: fileName,
      mimeType: mimeType,
      status: status,
      byteSize: byteSize,
      localPath: localPath,
      thumbnailPath: thumbnailPath,
      sha256: sha256,
      errorCode: errorCode,
      errorMessage: errorMessage,
      providerFileRefJson: providerFileRefJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  final String localId;
  final ChatAttachmentKind kind;
  final ChatAttachmentSource source;
  final String fileName;
  final String mimeType;
  final int? byteSize;
  final String? localPath;
  final String? thumbnailPath;
  final String? sha256;
  final ChatAttachmentStatus status;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic>? providerFileRefJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatAttachment copyWith({
    String? localId,
    ChatAttachmentKind? kind,
    ChatAttachmentSource? source,
    String? fileName,
    String? mimeType,
    int? byteSize,
    String? localPath,
    String? thumbnailPath,
    String? sha256,
    ChatAttachmentStatus? status,
    String? errorCode,
    String? errorMessage,
    Map<String, dynamic>? providerFileRefJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatAttachment(
      localId: localId ?? this.localId,
      kind: kind ?? this.kind,
      source: source ?? this.source,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      byteSize: byteSize ?? this.byteSize,
      localPath: localPath ?? this.localPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      sha256: sha256 ?? this.sha256,
      status: status ?? this.status,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      providerFileRefJson: providerFileRefJson ?? this.providerFileRefJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'localId': localId,
      'kind': kind.name,
      'source': source.name,
      'fileName': fileName,
      'mimeType': mimeType,
      'byteSize': byteSize,
      'localPath': localPath,
      'thumbnailPath': thumbnailPath,
      'sha256': sha256,
      'status': status.name,
      'errorCode': errorCode,
      'errorMessage': errorMessage,
      'providerFileRefJson': providerFileRefJson,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      localId: json['localId'] as String,
      kind: ChatAttachmentKind.values.byName(json['kind'] as String),
      source: ChatAttachmentSource.values.byName(json['source'] as String),
      fileName: json['fileName'] as String,
      mimeType: json['mimeType'] as String,
      byteSize: json['byteSize'] as int?,
      localPath: json['localPath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      sha256: json['sha256'] as String?,
      status: ChatAttachmentStatus.values.byName(json['status'] as String),
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
      providerFileRefJson:
          (json['providerFileRefJson'] as Map?)?.cast<String, dynamic>(),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
    );
  }

  Map<String, dynamic> toDatabaseMap({int? messageId}) {
    return {
      'message_id': messageId,
      'local_attachment_id': localId,
      'kind': kind.name,
      'source': source.name,
      'file_name': fileName,
      'mime_type': mimeType,
      'byte_size': byteSize,
      'local_path': localPath,
      'thumbnail_path': thumbnailPath,
      'sha256': sha256,
      'status': status.name,
      'error_code': errorCode,
      'error_message': errorMessage,
      'provider_file_ref_json': providerFileRefJson == null
          ? null
          : jsonEncode(providerFileRefJson),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ChatAttachment.fromDatabaseMap(Map<String, dynamic> map) {
    return ChatAttachment(
      localId: map['local_attachment_id'] as String,
      kind: ChatAttachmentKind.values.byName(map['kind'] as String),
      source: ChatAttachmentSource.values.byName(map['source'] as String),
      fileName: map['file_name'] as String,
      mimeType: map['mime_type'] as String,
      byteSize: map['byte_size'] as int?,
      localPath: map['local_path'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      sha256: map['sha256'] as String?,
      status: ChatAttachmentStatus.values.byName(map['status'] as String),
      errorCode: map['error_code'] as String?,
      errorMessage: map['error_message'] as String?,
      providerFileRefJson: _decodeProviderRef(map['provider_file_ref_json']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  static Map<String, dynamic>? _decodeProviderRef(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    }
    return null;
  }
}
