String fileHighlightLanguageForPath(String filePath) {
  final normalized = filePath.trim().toLowerCase();
  final dotIndex = normalized.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == normalized.length - 1) {
    return 'plaintext';
  }

  final extension = normalized.substring(dotIndex + 1);
  switch (extension) {
    case 'dart':
      return 'dart';
    case 'md':
    case 'markdown':
      return 'markdown';
    case 'json':
      return 'json';
    case 'yaml':
    case 'yml':
      return 'yaml';
    case 'js':
      return 'javascript';
    case 'ts':
      return 'typescript';
    case 'css':
      return 'css';
    case 'html':
    case 'htm':
      return 'xml';
    case 'sh':
      return 'bash';
    default:
      return 'plaintext';
  }
}
