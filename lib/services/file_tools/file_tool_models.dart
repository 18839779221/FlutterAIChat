class FileToolPathResolution {
  final bool isValid;
  final String? relativePath;
  final String? absolutePath;
  final String? errorCode;

  const FileToolPathResolution._({
    required this.isValid,
    this.relativePath,
    this.absolutePath,
    this.errorCode,
  });

  const FileToolPathResolution.valid({
    required String relativePath,
    required String absolutePath,
  }) : this._(
          isValid: true,
          relativePath: relativePath,
          absolutePath: absolutePath,
        );

  const FileToolPathResolution.invalid({
    required String errorCode,
  }) : this._(
          isValid: false,
          errorCode: errorCode,
        );
}

class FileToolVersionSnapshot {
  final int modifiedAtMillis;
  final int sizeBytes;

  const FileToolVersionSnapshot({
    required this.modifiedAtMillis,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() {
    return {
      'modifiedAtMillis': modifiedAtMillis,
      'sizeBytes': sizeBytes,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is FileToolVersionSnapshot &&
        other.modifiedAtMillis == modifiedAtMillis &&
        other.sizeBytes == sizeBytes;
  }

  @override
  int get hashCode => Object.hash(modifiedAtMillis, sizeBytes);
}

class FileToolDirectoryEntry {
  final String name;
  final String relativePath;
  final bool isDirectory;
  final int? sizeBytes;

  const FileToolDirectoryEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    this.sizeBytes,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'relativePath': relativePath,
      'isDirectory': isDirectory,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
    };
  }
}

class FileToolGrepMatch {
  final String filePath;
  final int? lineNumber;
  final String lineText;

  const FileToolGrepMatch({
    required this.filePath,
    this.lineNumber,
    required this.lineText,
  });

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      if (lineNumber != null) 'lineNumber': lineNumber,
      'lineText': lineText,
    };
  }
}

class FileToolBudgetApplyResult {
  final List<String> lines;
  final bool truncated;

  const FileToolBudgetApplyResult({
    required this.lines,
    required this.truncated,
  });
}

class FileToolReadFormatResult {
  final String content;
  final int startLine;
  final int totalLines;
  final int linesReturned;
  final bool truncated;

  const FileToolReadFormatResult({
    required this.content,
    required this.startLine,
    required this.totalLines,
    required this.linesReturned,
    required this.truncated,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'startLine': startLine,
      'totalLines': totalLines,
      'linesReturned': linesReturned,
      'truncated': truncated,
    };
  }
}
