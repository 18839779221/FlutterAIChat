import 'file_tool_models.dart';

class FileToolBudgetService {
  const FileToolBudgetService({
    this.maxLineLength = 2000,
    this.maxOutputCharacters = 20000,
  });

  final int maxLineLength;
  final int maxOutputCharacters;

  FileToolBudgetApplyResult apply(List<String> lines) {
    final normalizedLines = <String>[];
    var truncated = false;
    var usedCharacters = 0;

    for (final rawLine in lines) {
      var line = rawLine;
      if (line.length > maxLineLength) {
        line = '${line.substring(0, maxLineLength)}...';
        truncated = true;
      }

      final separatorLength = normalizedLines.isEmpty ? 0 : 1;
      if (usedCharacters + separatorLength + line.length >
          maxOutputCharacters) {
        truncated = true;
        break;
      }

      normalizedLines.add(line);
      usedCharacters += separatorLength + line.length;
    }

    return FileToolBudgetApplyResult(
      lines: normalizedLines,
      truncated: truncated,
    );
  }
}
