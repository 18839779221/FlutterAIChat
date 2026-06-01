class ChatAttachmentClassifier {
  static const Set<String> _supportedImageMimeTypes = <String>{
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };

  static bool isSupportedImageMimeType(String mimeType) {
    return _supportedImageMimeTypes.contains(mimeType.trim().toLowerCase());
  }
}
