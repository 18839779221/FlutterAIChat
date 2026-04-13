class FileToolPostWriteContext {
  final String filePath;
  final String? oldContent;
  final String newContent;

  const FileToolPostWriteContext({
    required this.filePath,
    required this.oldContent,
    required this.newContent,
  });
}

abstract class FileToolPostWriteHook {
  const FileToolPostWriteHook();

  Future<Map<String, dynamic>> afterWrite(FileToolPostWriteContext context);
}

class NoopFileToolPostWriteHook extends FileToolPostWriteHook {
  const NoopFileToolPostWriteHook();

  @override
  Future<Map<String, dynamic>> afterWrite(
      FileToolPostWriteContext context) async {
    return const {};
  }
}
