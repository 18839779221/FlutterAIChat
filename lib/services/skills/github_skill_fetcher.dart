import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/skill/github_skill_source.dart';
import 'skill_installer_service.dart';

class GitHubSkillFetcher implements SkillSourceFetcher {
  GitHubSkillFetcher({
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<Map<String, String>> fetchSkillFiles(GitHubSkillSource source) async {
    final files = <String, String>{};
    await _collectDirectory(
      source: source,
      remotePath: source.subdirectory ?? '',
      relativePrefix: '',
      files: files,
    );
    return files;
  }

  Future<void> _collectDirectory({
    required GitHubSkillSource source,
    required String remotePath,
    required String relativePrefix,
    required Map<String, String> files,
  }) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/${source.owner}/${source.repo}/contents/$remotePath',
      source.ref == null ? null : {'ref': source.ref!},
    );
    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/vnd.github+json',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SkillInstallerException(
        'GitHub request failed (${response.statusCode}) for $uri',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      await _collectFileObject(
        decoded,
        relativePrefix: relativePrefix,
        files: files,
      );
      return;
    }
    if (decoded is! List) {
      throw const SkillInstallerException('Unexpected GitHub contents response.');
    }

    for (final item in decoded.whereType<Map>()) {
      final object = Map<String, dynamic>.from(item);
      final type = (object['type'] ?? '').toString();
      final name = (object['name'] ?? '').toString();
      final path = (object['path'] ?? '').toString();
      if (type == 'file') {
        await _collectFileObject(
          object,
          relativePrefix: relativePrefix,
          files: files,
        );
        continue;
      }
      if (type == 'dir' && name.isNotEmpty && path.isNotEmpty) {
        final nextPrefix = relativePrefix.isEmpty ? name : '$relativePrefix/$name';
        await _collectDirectory(
          source: source,
          remotePath: path,
          relativePrefix: nextPrefix,
          files: files,
        );
      }
    }
  }

  Future<void> _collectFileObject(
    Map<String, dynamic> object, {
    required String relativePrefix,
    required Map<String, String> files,
  }) async {
    final downloadUrl = (object['download_url'] ?? '').toString();
    final name = (object['name'] ?? '').toString();
    if (downloadUrl.isEmpty || name.isEmpty) {
      throw const SkillInstallerException('Skill file is missing download metadata.');
    }
    final response = await _client.get(Uri.parse(downloadUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SkillInstallerException(
        'GitHub raw download failed (${response.statusCode}) for $downloadUrl',
      );
    }
    final relativePath = relativePrefix.isEmpty ? name : '$relativePrefix/$name';
    files[relativePath] = response.body;
  }
}
