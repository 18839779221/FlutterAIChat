import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/attachments/chat_attachment_picker_service.dart';
import 'package:ai_chat/services/attachments/chat_attachment_storage_service.dart';
import 'package:ai_chat/services/artifact/artifact_file_storage_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:ai_chat/services/follow_up_dispatch_queue.dart';
import 'package:ai_chat/services/skills/github_skill_fetcher.dart';
import 'package:ai_chat/services/skills/github_skill_source_resolver.dart';
import 'package:ai_chat/services/skills/skill_index_service.dart';
import 'package:ai_chat/services/skills/skill_installer_service.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime dependency bundle installed only after delayed bootstrap finishes.
class AppRuntime {
  const AppRuntime({
    required this.sharedPreferences,
    required this.appSettingsRepository,
    required this.chatStorage,
    required this.followUpDispatchQueue,
    required this.chatAttachmentPickerService,
    required this.chatAttachmentStorageService,
    required this.artifactFileStorageService,
    required this.fileToolRootService,
    required this.skillStorageService,
    required this.gitHubSkillSourceResolver,
    required this.gitHubSkillFetcher,
    required this.skillIndexService,
    required this.skillRuntimeService,
    required this.skillInstallerService,
    required this.traceRecorder,
    required this.chatService,
    required this.turnHarness,
  });

  final SharedPreferences sharedPreferences;
  final AppSettingsRepository appSettingsRepository;
  final ChatStorage chatStorage;
  final FollowUpDispatchQueue followUpDispatchQueue;
  final ChatAttachmentPickerService? chatAttachmentPickerService;
  final ChatAttachmentStorageService? chatAttachmentStorageService;
  final ArtifactFileStorageService? artifactFileStorageService;
  final FileToolRootService? fileToolRootService;
  final SkillStorageService skillStorageService;
  final GitHubSkillSourceResolver gitHubSkillSourceResolver;
  final GitHubSkillFetcher gitHubSkillFetcher;
  final SkillIndexService skillIndexService;
  final SkillRuntimeService skillRuntimeService;
  final SkillInstallerService skillInstallerService;
  final ChatTraceRecorder traceRecorder;
  final ChatService chatService;
  final TurnHarness? turnHarness;
}
