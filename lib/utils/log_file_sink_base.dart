abstract class LogFileSink {
  String get filePath;

  Future<void> writeLine(String line);
}
