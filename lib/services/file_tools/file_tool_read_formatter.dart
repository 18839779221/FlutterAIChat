import 'file_tool_models.dart';

class FileToolReadFormatter {
  const FileToolReadFormatter();

  FileToolReadFormatResult format({
    required String filePath,
    required List<String> lines,
    required int startLine,
    required int totalLines,
    required bool truncated,
  }) {
    final lineNumberWidth =
        totalLines.toString().length < 6 ? 6 : totalLines.toString().length;
    final renderedLines = <String>[];

    for (var index = 0; index < lines.length; index++) {
      final lineNumber = startLine + index;
      renderedLines.add(
          '${lineNumber.toString().padLeft(lineNumberWidth)}\t${lines[index]}');
    }

    return FileToolReadFormatResult(
      content: renderedLines.join('\n'),
      startLine: startLine,
      totalLines: totalLines,
      linesReturned: lines.length,
      truncated: truncated,
    );
  }
}
