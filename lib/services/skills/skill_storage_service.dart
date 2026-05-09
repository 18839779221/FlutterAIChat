import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef SkillsRootDirectoryProvider = Future<Directory> Function();

class SkillStorageService {
  SkillStorageService({
    SkillsRootDirectoryProvider? rootDirectoryProvider,
  }) : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationSupportDirectory;

  final SkillsRootDirectoryProvider _rootDirectoryProvider;

  Future<Directory> skillsRootDirectory() async {
    final root = await _rootDirectoryProvider();
    final directory = Directory(p.join(root.path, 'skills'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> installedSkillsDirectory() async {
    final root = await skillsRootDirectory();
    final directory = Directory(p.join(root.path, 'installed'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> skillDirectory(String skillId) async {
    final installedRoot = await installedSkillsDirectory();
    return Directory(p.join(installedRoot.path, skillId));
  }
}
