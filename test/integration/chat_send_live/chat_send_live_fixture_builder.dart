import 'dart:io';
import 'package:path/path.dart' as path;

class ChatSendLiveFixtureBuilder {
  Future<Directory> createWorkspaceRoot({
    required String scenarioId,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'chat_send_live_${scenarioId}_',
    );
    return root;
  }

  Future<Directory> createWorkspace({
    required String scenarioId,
    Map<String, String> files = const {},
  }) async {
    final root = await createWorkspaceRoot(scenarioId: scenarioId);
    await populateWorkspace(root: root, files: files);
    return root;
  }

  Future<void> populateWorkspace({
    required Directory root,
    Map<String, String> files = const {},
  }) async {
    for (final entry in files.entries) {
      final file = File(path.join(root.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
  }
}
