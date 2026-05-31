import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/models/speech/speech_input_config.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/audio/audio_capture_service.dart';
import 'package:ai_chat/services/audio/record_audio_capture_service.dart';
import 'package:ai_chat/services/artifact/artifact_file_storage_service.dart';
import 'package:ai_chat/services/artifact/artifact_guideline_contract_builder.dart';
import 'package:ai_chat/services/artifact/artifact_theme_token_mapper.dart';
import 'package:ai_chat/services/artifact/artifact_turn_resolver.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_timeline_projection_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/latest_message_running_status_resolver.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:ai_chat/repositories/session_runtime_marker_repository.dart';
import 'package:ai_chat/services/prompt/runtime_user_context_service.dart';
import 'package:ai_chat/services/session_context_projector.dart';
import 'package:ai_chat/services/session_context_inspector_service.dart';
import 'package:ai_chat/services/session_context_service.dart';
import 'package:ai_chat/services/session_runtime_marker_service.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:ai_chat/services/skills/github_skill_fetcher.dart';
import 'package:ai_chat/services/skills/github_skill_source_resolver.dart';
import 'package:ai_chat/services/skills/skill_index_service.dart';
import 'package:ai_chat/services/skills/skill_installer_service.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/services/speech/aliyun_realtime_asr_client.dart';
import 'package:ai_chat/services/speech/aliyun_speech_to_text_service.dart';
import 'package:ai_chat/services/speech/speech_to_text_service.dart';
import 'package:ai_chat/services/tool_presentation_block_projector.dart';
import 'package:ai_chat/services/tool_ui_renderer_registry.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:ai_chat/widgets/tool_renderers/compact_tool_row_renderer.dart';
import 'package:ai_chat/widgets/tool_renderers/create_artifact_guideline_tool_renderer.dart';
import 'package:ai_chat/widgets/tool_renderers/create_artifact_tool_renderer.dart';
import 'package:ai_chat/widgets/tool_renderers/edit_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/web_search_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/write_tool_workflow_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';

// 数据库提供者（实际实现在 main.dart 中通过 override 注入）
final databaseProvider = Provider<ChatStorage>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖 databaseProvider');
});

/// App-wide shared preferences used for lightweight UI state only.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖 sharedPreferencesProvider');
});

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖 AppSettingsRepository');
});

final speechInputConfigProvider = FutureProvider<SpeechInputConfig?>((ref) async {
  return ref.read(appSettingsRepositoryProvider).getSpeechInputConfig();
});

final audioCaptureServiceProvider = Provider<AudioCaptureService?>((ref) {
  final config = ref.watch(speechInputConfigProvider).valueOrNull;
  if (config == null || !config.isValid) {
    return null;
  }
  final service = RecordAudioCaptureService();
  ref.onDispose(service.dispose);
  return service;
});

final aliyunRealtimeAsrClientProvider = Provider<AliyunRealtimeAsrClient?>(
  (ref) {
    final config = ref.watch(speechInputConfigProvider).valueOrNull;
    if (config == null || !config.isValid) {
      return null;
    }
    if (config.provider != 'aliyun') {
      return null;
    }

    final client = DashScopeAliyunRealtimeAsrClient(config: config);
    ref.onDispose(() {
      client.close();
    });
    return client;
  },
);

final speechToTextServiceProvider = Provider<SpeechToTextService?>((ref) {
  final client = ref.watch(aliyunRealtimeAsrClientProvider);
  final configAsync = ref.watch(speechInputConfigProvider);
  final config = configAsync.valueOrNull;
  if (client == null || config == null || !config.isValid) {
    return null;
  }
  if (config.provider != 'aliyun') {
    return null;
  }
  return AliyunSpeechToTextService(client: client);
});

final traceRecorderProvider = Provider<ChatTraceRecorder>((ref) {
  return ChatTraceRecorder();
});

final latestMessageRunningStatusResolverProvider =
    Provider<LatestMessageRunningStatusResolver>((ref) {
  return const LatestMessageRunningStatusResolver();
});

final toolUiRendererRegistryProvider = Provider<ToolUiRendererRegistry>((ref) {
  return const ToolUiRendererRegistry(
    renderers: [
      CompactToolRowToolUiRenderer(
        toolName: 'Read',
        workflowMapper: _buildReadWorkflowRow,
        resultMapper: _buildReadResultRow,
      ),
      CompactToolRowToolUiRenderer(
        toolName: 'LS',
        workflowMapper: _buildLsWorkflowRow,
        resultMapper: _buildLsResultRow,
      ),
      CompactToolRowToolUiRenderer(
        toolName: 'Grep',
        workflowMapper: _buildGrepWorkflowRow,
        resultMapper: _buildGrepResultRow,
      ),
      CompactToolRowToolUiRenderer(
        toolName: 'Glob',
        workflowMapper: _buildGlobWorkflowRow,
        resultMapper: _buildGlobResultRow,
      ),
      WriteToolUiRenderer(),
      EditToolUiRenderer(),
      CreateArtifactGuidelineToolUiRenderer(),
      CreateArtifactToolUiRenderer(),
      WebSearchToolUiRenderer(),
      FetchWebpageToolUiRenderer(),
    ],
  );
});

final chatTimelineProjectionServiceProvider =
    Provider<ChatTimelineProjectionService>((ref) {
  final artifactFileStorage = ref.watch(artifactFileStorageServiceProvider);
  return ChatTimelineProjectionService(
    artifactTurnResolver: artifactFileStorage == null
        ? null
        : ArtifactTurnResolver(fileStorageService: artifactFileStorage),
    toolBlockProjector: ToolPresentationBlockProjector(
      registry: ref.watch(toolUiRendererRegistryProvider),
    ),
  );
});

final artifactFileStorageServiceProvider =
    Provider<ArtifactFileStorageService?>((ref) => null);

final artifactThemeTokenMapperProvider =
    Provider<ArtifactThemeTokenMapper>((ref) => const ArtifactThemeTokenMapper());

final artifactGuidelineContractBuilderProvider =
    Provider<ArtifactGuidelineContractBuilder>(
  (ref) => const ArtifactGuidelineContractBuilder(),
);

// 聊天服务提供者
final chatServiceProvider = Provider<ChatService>((ref) {
  return ref.watch(chatServiceFactoryProvider);
});

// 聊天服务工厂提供者
final chatServiceFactoryProvider = Provider<ChatService>((ref) {
  throw UnimplementedError("需要在 main.dart 中覆盖创建 ChatService 的代码");
});

final chatTurnRepositoryProvider = Provider<ChatTurnRepository>((ref) {
  return ChatTurnRepository(ref.watch(databaseProvider));
});

final chatEventRepositoryProvider = Provider<ChatEventRepository>((ref) {
  return ChatEventRepository(ref.watch(databaseProvider));
});

final sessionContextSnapshotRepositoryProvider =
    Provider<SessionContextSnapshotRepository>((ref) {
  return SessionContextSnapshotRepository(ref.watch(databaseProvider));
});

final sessionRuntimeMarkerRepositoryProvider =
    Provider<SessionRuntimeMarkerRepository>((ref) {
  return SessionRuntimeMarkerRepository(ref.watch(databaseProvider));
});

final sessionContextProjectorProvider =
    Provider<SessionContextProjector>((ref) => SessionContextProjector());

final runtimeUserContextServiceProvider = Provider<RuntimeUserContextService>(
  (ref) => RuntimeUserContextService(
    skillCatalogProvider: () async {
      return ref.read(skillRuntimeServiceProvider).listSkillCatalogEntries();
    },
  ),
);

final enabledSkillCatalogProvider = FutureProvider<List<SkillCatalogEntry>>((ref) {
  return ref.read(skillRuntimeServiceProvider).listSkillCatalogEntries();
});

final skillStorageServiceProvider = Provider<SkillStorageService>((ref) {
  return SkillStorageService();
});

final gitHubSkillSourceResolverProvider =
    Provider<GitHubSkillSourceResolver>((ref) {
  return const GitHubSkillSourceResolver();
});

final gitHubSkillFetcherProvider = Provider<GitHubSkillFetcher>((ref) {
  return GitHubSkillFetcher();
});

final skillIndexServiceProvider = Provider<SkillIndexService>((ref) {
  return SkillIndexService(
    storageService: ref.watch(skillStorageServiceProvider),
  );
});

final skillRuntimeServiceProvider = Provider<SkillRuntimeService>((ref) {
  return SkillRuntimeService(
    storageService: ref.watch(skillStorageServiceProvider),
    settingsRepository: ref.watch(appSettingsRepositoryProvider),
    indexService: ref.watch(skillIndexServiceProvider),
  );
});

final skillInstallerServiceProvider = Provider<SkillInstallerService>((ref) {
  return SkillInstallerService(
    storageService: ref.watch(skillStorageServiceProvider),
    sourceResolver: ref.watch(gitHubSkillSourceResolverProvider),
    fetcher: ref.watch(gitHubSkillFetcherProvider),
  );
});

final sessionRuntimeMarkerServiceProvider =
    Provider<SessionRuntimeMarkerService>((ref) {
  return SessionRuntimeMarkerService(
    repository: ref.watch(sessionRuntimeMarkerRepositoryProvider),
  );
});

final modelBudgetRegistryProvider =
    Provider<ModelBudgetRegistry>((ref) => ModelBudgetRegistry());

final sessionTokenBudgetServiceProvider = Provider<SessionTokenBudgetService>(
  (ref) => SessionTokenBudgetService(
    modelBudgetRegistry: ref.watch(modelBudgetRegistryProvider),
  ),
);

final sessionSummaryServiceProvider = Provider<SessionSummaryService>((ref) {
  return SessionSummaryService(chatService: ref.watch(chatServiceProvider));
});

final sessionContextServiceProvider = Provider<SessionContextService>((ref) {
  return SessionContextService(
    chatTurnRepository: ref.watch(chatTurnRepositoryProvider),
    chatEventRepository: ref.watch(chatEventRepositoryProvider),
    snapshotRepository: ref.watch(sessionContextSnapshotRepositoryProvider),
    contextProjector: ref.watch(sessionContextProjectorProvider),
    tokenBudgetService: ref.watch(sessionTokenBudgetServiceProvider),
    summaryService: ref.watch(sessionSummaryServiceProvider),
    chatService: ref.watch(chatServiceProvider),
    runtimeUserContextService: ref.watch(runtimeUserContextServiceProvider),
  );
});

final sessionContextInspectorServiceProvider =
    Provider<SessionContextInspectorService>((ref) {
  return SessionContextInspectorService(
    sessionContextService: ref.watch(sessionContextServiceProvider),
    tokenBudgetService: ref.watch(sessionTokenBudgetServiceProvider),
    chatTurnRepository: ref.watch(chatTurnRepositoryProvider),
    chatEventRepository: ref.watch(chatEventRepositoryProvider),
  );
});

final turnHarnessProvider = Provider<TurnHarness?>((ref) => null);

CompactToolRowModel _buildReadWorkflowRow(List<ToolWorkflowStep> steps) {
  final latestStep = steps.isEmpty ? null : steps.last;
  final filePath = latestStep == null
      ? ''
      : (latestStep.details['file_path'] ?? '').toString().trim();
  return CompactToolRowModel(
    actionLabel: '读取',
    primaryText: filePath.isEmpty ? '已读取文件' : filePath,
    statusLabel: latestStep == null ? '已提议' : _statusLabelForStep(latestStep),
    status: _statusForStep(latestStep),
    isRunning: latestStep?.status == ToolWorkflowStepStatus.running,
  );
}

CompactToolRowModel _buildReadResultRow(ToolResult result) {
  final filePath = (result.data['filePath'] ?? '').toString().trim();
  return CompactToolRowModel(
    actionLabel: '读取',
    primaryText: filePath.isEmpty ? '已读取文件' : filePath,
    statusLabel: result.statusLabel,
    status: _statusForResult(result),
    isRunning: false,
  );
}

CompactToolRowModel _buildLsWorkflowRow(List<ToolWorkflowStep> steps) {
  final latestStep = steps.isEmpty ? null : steps.last;
  final pathValue =
      latestStep == null ? '' : (latestStep.details['path'] ?? '').toString();
  return CompactToolRowModel(
    actionLabel: '列目录',
    primaryText: _compactDirectoryPath(pathValue),
    statusLabel: latestStep == null ? '已提议' : _statusLabelForStep(latestStep),
    status: _statusForStep(latestStep),
    isRunning: latestStep?.status == ToolWorkflowStepStatus.running,
  );
}

CompactToolRowModel _buildLsResultRow(ToolResult result) {
  final pathValue = (result.data['path'] ?? '').toString();
  return CompactToolRowModel(
    actionLabel: '列目录',
    primaryText: _compactDirectoryPath(pathValue),
    statusLabel: result.statusLabel,
    status: _statusForResult(result),
    isRunning: false,
  );
}

CompactToolRowModel _buildGrepWorkflowRow(List<ToolWorkflowStep> steps) {
  final latestStep = steps.isEmpty ? null : steps.last;
  final pattern = latestStep == null
      ? ''
      : (latestStep.details['pattern'] ?? '').toString();
  final pathValue =
      latestStep == null ? '' : (latestStep.details['path'] ?? '').toString();
  return CompactToolRowModel(
    actionLabel: '搜索',
    primaryText: _grepPrimaryText(pattern: pattern, pathValue: pathValue),
    statusLabel: latestStep == null ? '已提议' : _statusLabelForStep(latestStep),
    status: _statusForStep(latestStep),
    isRunning: latestStep?.status == ToolWorkflowStepStatus.running,
  );
}

CompactToolRowModel _buildGrepResultRow(ToolResult result) {
  return CompactToolRowModel(
    actionLabel: '搜索',
    primaryText: _grepPrimaryText(
      pattern: (result.data['pattern'] ?? '').toString(),
      pathValue: (result.data['path'] ?? '').toString(),
    ),
    statusLabel: result.statusLabel,
    status: _statusForResult(result),
    isRunning: false,
  );
}

CompactToolRowModel _buildGlobWorkflowRow(List<ToolWorkflowStep> steps) {
  final latestStep = steps.isEmpty ? null : steps.last;
  final pattern = latestStep == null
      ? ''
      : (latestStep.details['pattern'] ?? '').toString();
  final pathValue =
      latestStep == null ? '' : (latestStep.details['path'] ?? '').toString();
  return CompactToolRowModel(
    actionLabel: '查找文件',
    primaryText: _globPrimaryText(pattern: pattern, pathValue: pathValue),
    statusLabel: latestStep == null ? '已提议' : _statusLabelForStep(latestStep),
    status: _statusForStep(latestStep),
    isRunning: latestStep?.status == ToolWorkflowStepStatus.running,
  );
}

CompactToolRowModel _buildGlobResultRow(ToolResult result) {
  return CompactToolRowModel(
    actionLabel: '查找文件',
    primaryText: _globPrimaryText(
      pattern: (result.data['pattern'] ?? '').toString(),
      pathValue: (result.data['path'] ?? '').toString(),
    ),
    statusLabel: result.statusLabel,
    status: _statusForResult(result),
    isRunning: false,
  );
}

String _statusLabelForStep(ToolWorkflowStep step) {
  switch (step.status) {
    case ToolWorkflowStepStatus.awaitingConfirmation:
      return '待确认';
    case ToolWorkflowStepStatus.running:
      return '执行中';
    case ToolWorkflowStepStatus.completed:
      return '完成';
    case ToolWorkflowStepStatus.failed:
      return '失败';
    case ToolWorkflowStepStatus.cancelled:
      return '已取消';
    case ToolWorkflowStepStatus.proposed:
      return '已提议';
  }
}

/// 将工作流 step 映射到紧凑工具行的语义状态。
/// 颜色由 widget 端从主题 token 解析，不在这里烘焙具体 Color。
CompactToolRowStatus _statusForStep(ToolWorkflowStep? step) {
  switch (step?.status) {
    case ToolWorkflowStepStatus.completed:
      return CompactToolRowStatus.success;
    case ToolWorkflowStepStatus.failed:
    case ToolWorkflowStepStatus.cancelled:
      return CompactToolRowStatus.warning;
    case ToolWorkflowStepStatus.awaitingConfirmation:
    case ToolWorkflowStepStatus.running:
    case ToolWorkflowStepStatus.proposed:
    case null:
      return CompactToolRowStatus.running;
  }
}

/// 将工具最终结果映射到紧凑工具行的语义状态。
CompactToolRowStatus _statusForResult(ToolResult result) {
  return result.status == ToolExecutionStatus.success
      ? CompactToolRowStatus.success
      : CompactToolRowStatus.warning;
}

String _compactDirectoryPath(String rawPath) {
  final normalized = rawPath.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) {
    return '.';
  }

  final segments = normalized
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList();
  if (segments.isEmpty) {
    return normalized;
  }
  return _compactDirectory(segments);
}

String _grepPrimaryText({
  required String pattern,
  required String pathValue,
}) {
  final trimmedPattern = pattern.trim();
  final trimmedPath = pathValue.trim();
  if (trimmedPattern.isEmpty && trimmedPath.isEmpty) {
    return '文件内容';
  }
  if (trimmedPattern.isEmpty) {
    return _compactDirectoryPath(trimmedPath);
  }
  final quotedPattern = '"${_compactPattern(trimmedPattern)}"';
  if (trimmedPath.isEmpty) {
    return quotedPattern;
  }
  return '$quotedPattern · ${_compactDirectoryPath(trimmedPath)}';
}

String _globPrimaryText({
  required String pattern,
  required String pathValue,
}) {
  final trimmedPattern = pattern.trim();
  final trimmedPath = pathValue.trim();
  if (trimmedPattern.isEmpty && trimmedPath.isEmpty) {
    return '匹配路径';
  }
  if (trimmedPattern.isEmpty) {
    return _compactDirectoryPath(trimmedPath);
  }
  final compactPattern = _compactPattern(trimmedPattern);
  if (trimmedPath.isEmpty) {
    return compactPattern;
  }
  return '$compactPattern · ${_compactDirectoryPath(trimmedPath)}';
}

String _compactDirectory(List<String> segments) {
  if (segments.isEmpty) {
    return '';
  }
  if (segments.length <= 3) {
    return segments.join('/');
  }
  return '${segments.first}/${segments[1]}/.../${segments.last}';
}

String _compactPattern(String value) {
  if (value.length <= 32) {
    return value;
  }
  return '${value.substring(0, 14)}...${value.substring(value.length - 12)}';
}
