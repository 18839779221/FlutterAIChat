import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/skill/github_skill_source.dart';
import '../models/skill/skill_catalog_entry.dart';
import '../models/skill/skill_descriptor.dart';
import '../repositories/app_settings_repository.dart';
import '../services/attachments/chat_attachment_storage_service.dart';
import '../services/artifact/artifact_file_storage_service.dart';
import '../services/default_file_tool_adapters.dart';
import '../services/file_tools/file_tool_host_adapters.dart';
import '../services/skills/github_skill_fetcher.dart';
import '../services/skills/github_skill_source_resolver.dart';
import '../services/skills/skill_index_service.dart';
import '../services/skills/skill_installer_service.dart';
import '../services/skills/skill_runtime_service.dart';
import '../services/skills/skill_storage_service.dart';
import '../storage/chat_storage.dart';

typedef AppSupportDirectoryProvider = Future<Directory> Function();

/// Host-backed runtime services that depend on filesystem availability.
class RuntimeHostServices {
  const RuntimeHostServices({
    required this.artifactFileStorageService,
    required this.chatAttachmentStorageService,
    required this.fileToolAdapters,
    required this.skillStorageService,
    required this.skillIndexService,
    required this.skillRuntimeService,
    required this.skillInstallerService,
  });

  final ArtifactFileStorageService? artifactFileStorageService;
  final ChatAttachmentStorageService? chatAttachmentStorageService;
  final FileToolHostAdapters? fileToolAdapters;
  final SkillStorageService skillStorageService;
  final SkillIndexService skillIndexService;
  final SkillRuntimeService skillRuntimeService;
  final SkillInstallerService skillInstallerService;
}

Future<RuntimeHostServices> buildRuntimeHostServices({
  required bool isWeb,
  required ChatStorage storage,
  required AppSettingsRepository settingsRepository,
  AppSupportDirectoryProvider appSupportDirectoryProvider =
      getApplicationSupportDirectory,
}) async {
  if (isWeb) {
    final skillStorageService = _UnsupportedSkillStorageService();
    final skillIndexService = SkillIndexService(
      storageService: skillStorageService,
    );
    final skillRuntimeService = _WebSkillRuntimeService(
      storageService: skillStorageService,
      settingsRepository: settingsRepository,
      indexService: skillIndexService,
    );
    final skillInstallerService = _WebSkillInstallerService(
      storageService: skillStorageService,
      sourceResolver: const GitHubSkillSourceResolver(),
      fetcher: const _UnsupportedSkillSourceFetcher(),
    );
    return RuntimeHostServices(
      artifactFileStorageService: null,
      chatAttachmentStorageService: null,
      fileToolAdapters: null,
      skillStorageService: skillStorageService,
      skillIndexService: skillIndexService,
      skillRuntimeService: skillRuntimeService,
      skillInstallerService: skillInstallerService,
    );
  }

  final fileToolAdapters = await buildDefaultFileToolHostAdapters();
  final appSupportDirectory = await appSupportDirectoryProvider();
  final agentRootDirectory = Directory(
    path.join(appSupportDirectory.path, 'agent'),
  );
  final artifactFileStorageService = ArtifactFileStorageService(
    rootDirectory: agentRootDirectory,
    workspaceIdResolver: (groupId) async {
      return (await storage.getGroupById(groupId))?.workspaceId;
    },
  );
  final skillStorageService = SkillStorageService(
    rootDirectoryProvider: () async => agentRootDirectory,
  );
  final skillIndexService = SkillIndexService(
    storageService: skillStorageService,
  );
  final skillRuntimeService = SkillRuntimeService(
    storageService: skillStorageService,
    settingsRepository: settingsRepository,
    indexService: skillIndexService,
  );
  final skillInstallerService = SkillInstallerService(
    storageService: skillStorageService,
    sourceResolver: const GitHubSkillSourceResolver(),
    fetcher: GitHubSkillFetcher(),
  );
  await artifactFileStorageService.ensureReady();
  final chatAttachmentStorageService = ChatAttachmentStorageService(
    resolveRootDirectory: () async => agentRootDirectory,
  );
  return RuntimeHostServices(
    artifactFileStorageService: artifactFileStorageService,
    chatAttachmentStorageService: chatAttachmentStorageService,
    fileToolAdapters: fileToolAdapters,
    skillStorageService: skillStorageService,
    skillIndexService: skillIndexService,
    skillRuntimeService: skillRuntimeService,
    skillInstallerService: skillInstallerService,
  );
}

class _WebSkillRuntimeService extends SkillRuntimeService {
  _WebSkillRuntimeService({
    required super.storageService,
    super.settingsRepository,
    super.indexService,
  });

  @override
  Future<List<SkillDescriptor>> listAvailableSkills() async => const [];

  @override
  Future<List<SkillDescriptor>> listInstalledSkills() async => const [];

  @override
  Future<List<SkillCatalogEntry>> listSkillCatalogEntries() async => const [];

  @override
  Future<SkillDescriptor?> loadSkillById(String skillId) async => null;
}

class _WebSkillInstallerService extends SkillInstallerService {
  _WebSkillInstallerService({
    required super.storageService,
    required super.sourceResolver,
    required super.fetcher,
  });

  static const String _unsupportedMessage = 'Web 平台暂不支持本地 Skill 安装。';

  @override
  Future<SkillInstallPreview> previewFromGitHubUrl(String input) {
    throw const SkillInstallerException(_unsupportedMessage);
  }

  @override
  Future<SkillInstallResult> installFromGitHubUrl(String input) {
    throw const SkillInstallerException(_unsupportedMessage);
  }
}

class _UnsupportedSkillStorageService extends SkillStorageService {
  _UnsupportedSkillStorageService()
      : super(
          rootDirectoryProvider: _unsupportedRootDirectoryProvider,
        );

  static Future<Directory> _unsupportedRootDirectoryProvider() async {
    throw UnsupportedError('Web 平台不提供本地 skills 目录。');
  }
}

class _UnsupportedSkillSourceFetcher implements SkillSourceFetcher {
  const _UnsupportedSkillSourceFetcher();

  @override
  Future<Map<String, String>> fetchSkillFiles(GitHubSkillSource source) async {
    throw const SkillInstallerException('Web 平台暂不支持本地 Skill 安装。');
  }
}
