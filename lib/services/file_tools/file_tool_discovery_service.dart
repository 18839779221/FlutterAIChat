import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'file_tool_budget_service.dart';
import 'file_tool_models.dart';
import 'file_tool_path_policy.dart';
import 'file_tool_root_service.dart';

class FileToolDiscoveryService {
  FileToolDiscoveryService({
    required FileToolRootService rootService,
    required FileToolPathPolicy pathPolicy,
    FileToolBudgetService budgetService = const FileToolBudgetService(),
  })  : _rootService = rootService,
        _pathPolicy = pathPolicy,
        _budgetService = budgetService;

  final FileToolRootService _rootService;
  final FileToolPathPolicy _pathPolicy;
  final FileToolBudgetService _budgetService;

  Future<List<FileToolDirectoryEntry>> list({
    required String pathValue,
    required String cwd,
    List<String> ignore = const [],
  }) async {
    final resolution = _pathPolicy.normalizeDirectoryPath(
      pathValue,
      cwd: cwd,
    );
    if (!resolution.isValid || resolution.absolutePath == null) {
      return const [];
    }

    final directory = Directory(resolution.absolutePath!);
    if (!directory.existsSync()) {
      return const [];
    }

    final entries = <FileToolDirectoryEntry>[];
    final ignoreMatchers = ignore.map(_compileGlob).toList(growable: false);
    await for (final entity
        in directory.list(recursive: false, followLinks: false)) {
      final agentPath = _agentPathFor(entity.path);
      if (_matchesAnyGlob(agentPath, ignoreMatchers)) {
        continue;
      }
      final name = path.basename(entity.path);
      final stat = await entity.stat();
      entries.add(
        FileToolDirectoryEntry(
          name: name,
          relativePath: agentPath,
          isDirectory: entity is Directory,
          sizeBytes: entity is File ? stat.size : null,
        ),
      );
    }

    entries
        .sort((left, right) => left.relativePath.compareTo(right.relativePath));
    return entries;
  }

  Future<List<String>> glob({
    required String pattern,
    String? pathValue,
    required String cwd,
  }) async {
    final resolution = _pathPolicy.normalizeDirectoryPath(
      pathValue,
      cwd: cwd,
    );
    if (!resolution.isValid || resolution.absolutePath == null) {
      return const [];
    }

    final directory = Directory(resolution.absolutePath!);
    if (!directory.existsSync()) {
      return const [];
    }

    final matcher = _compileGlob(pattern);
    final baseRelativePath = resolution.relativePath ?? '';
    final matches = <String>[];
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final relativeFromBase =
          _relativeToBase(entity.path, resolution.absolutePath!);
      if (!matcher.hasMatch(relativeFromBase)) {
        continue;
      }
      matches.add(_joinAgentPath(baseRelativePath, relativeFromBase));
    }

    matches.sort();
    return matches;
  }

  Future<Map<String, dynamic>> grep({
    required String pattern,
    String? pathValue,
    String? glob,
    required String cwd,
    String outputMode = 'files_with_matches',
    int headLimit = 20,
    bool multiline = false,
    bool caseInsensitive = false,
    bool lineNumbers = false,
  }) async {
    final resolution = _pathPolicy.normalizeDirectoryPath(
      pathValue,
      cwd: cwd,
    );
    if (!resolution.isValid || resolution.absolutePath == null) {
      return const {
        'mode': 'files_with_matches',
        'files': [],
        'matches': [],
        'counts': {},
      };
    }

    final directory = Directory(resolution.absolutePath!);
    if (!directory.existsSync()) {
      return const {
        'mode': 'files_with_matches',
        'files': [],
        'matches': [],
        'counts': {},
      };
    }

    final contentMatcher = RegExp(
      pattern,
      multiLine: multiline,
      caseSensitive: !caseInsensitive,
    );
    final pathMatcher = glob == null ? null : _compileGlob(glob);
    final files = <String>[];
    final matches = <FileToolGrepMatch>[];
    final counts = <String, int>{};
    final baseRelativePath = resolution.relativePath ?? '';

    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final relativeFromBase =
          _relativeToBase(entity.path, resolution.absolutePath!);
      if (pathMatcher != null && !pathMatcher.hasMatch(relativeFromBase)) {
        continue;
      }
      if (await _isLikelyBinary(entity)) {
        continue;
      }

      final relativePath = _joinAgentPath(baseRelativePath, relativeFromBase);
      final text = await entity.readAsString();

      if (outputMode == 'count') {
        final count = contentMatcher.allMatches(text).length;
        if (count > 0) {
          counts[relativePath] = count;
        }
        continue;
      }

      if (outputMode == 'files_with_matches') {
        if (contentMatcher.hasMatch(text)) {
          files.add(relativePath);
        }
        continue;
      }

      final lines = const LineSplitter().convert(text);
      for (var index = 0; index < lines.length; index++) {
        if (!contentMatcher.hasMatch(lines[index])) {
          continue;
        }
        matches.add(
          FileToolGrepMatch(
            filePath: relativePath,
            lineNumber: lineNumbers ? index + 1 : null,
            lineText: lines[index],
          ),
        );
        if (matches.length >= headLimit) {
          break;
        }
      }
      if (matches.length >= headLimit) {
        break;
      }
    }

    final limitedMatches = outputMode == 'content'
        ? _budgetService.apply(matches.map((item) => item.lineText).toList())
        : null;
    final contentMatches = limitedMatches == null
        ? matches
        : [
            for (var index = 0; index < limitedMatches.lines.length; index++)
              FileToolGrepMatch(
                filePath: matches[index].filePath,
                lineNumber: matches[index].lineNumber,
                lineText: limitedMatches.lines[index],
              ),
          ];
    contentMatches.sort((left, right) {
      final fileComparison = left.filePath.compareTo(right.filePath);
      if (fileComparison != 0) {
        return fileComparison;
      }
      return (left.lineNumber ?? 0).compareTo(right.lineNumber ?? 0);
    });

    files.sort();
    return {
      'mode': outputMode,
      'files': files,
      'matches': contentMatches.map((item) => item.toJson()).toList(),
      'counts': counts,
    };
  }

  String _agentPathFor(String absolutePath) {
    final relative = path
        .relative(absolutePath, from: _rootService.rootPath)
        .replaceAll('\\', '/');
    if (relative.isEmpty || relative == '.') {
      return '/';
    }
    return '/$relative';
  }

  String _relativeToBase(String absolutePath, String basePath) {
    return path.relative(absolutePath, from: basePath).replaceAll('\\', '/');
  }

  String _joinAgentPath(String basePath, String childPath) {
    if (basePath.trim().isEmpty) {
      final normalized = childPath.replaceAll('\\', '/');
      return normalized.startsWith('/') ? normalized : '/$normalized';
    }
    final joined =
        path.normalize(path.join(basePath, childPath)).replaceAll('\\', '/');
    return joined.startsWith('/') ? joined : '/$joined';
  }

  RegExp _compileGlob(String pattern) {
    final buffer = StringBuffer('^');
    final normalized = pattern.replaceAll('\\', '/');
    for (var index = 0; index < normalized.length; index++) {
      final char = normalized[index];
      if (char == '*') {
        final hasNext = index + 1 < normalized.length;
        if (hasNext && normalized[index + 1] == '*') {
          final followedBySlash =
              index + 2 < normalized.length && normalized[index + 2] == '/';
          buffer.write(followedBySlash ? '(?:.*/)?' : '.*');
          index += followedBySlash ? 2 : 1;
          continue;
        }
        buffer.write('[^/]*');
        continue;
      }
      if (char == '?') {
        buffer.write('[^/]');
        continue;
      }
      if (r'\.+^$()[]{}|'.contains(char)) {
        buffer.write('\\$char');
        continue;
      }
      buffer.write(char);
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  bool _matchesAnyGlob(String value, List<RegExp> matchers) {
    for (final matcher in matchers) {
      if (matcher.hasMatch(value) || matcher.hasMatch(path.basename(value))) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _isLikelyBinary(File file) async {
    final bytes = await file.openRead(0, 512).fold<List<int>>(
      <int>[],
      (previous, element) => previous..addAll(element),
    );
    for (final byte in bytes) {
      if (byte == 0) {
        return true;
      }
    }
    return false;
  }
}
