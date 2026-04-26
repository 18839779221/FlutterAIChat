import 'package:ai_chat/controllers/chat_controller.dart';
import 'package:ai_chat/controllers/chat_interaction_coordinator.dart';
import 'package:ai_chat/controllers/chat_preferences_controller.dart';
import 'package:ai_chat/controllers/chat_send_coordinator.dart';
import 'package:ai_chat/controllers/chat_session_coordinator.dart';
import 'package:ai_chat/controllers/chat_summary_controller.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/tool_ui_renderer_registry.dart';
import 'package:ai_chat/widgets/tool_renderers/edit_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/compact_tool_row_renderer.dart';
import 'package:ai_chat/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/web_search_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/write_tool_workflow_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export '../controllers/chat_controller.dart';
export '../controllers/chat_interaction_coordinator.dart';
export '../controllers/chat_preferences_controller.dart';
export '../controllers/chat_send_coordinator.dart';
export '../controllers/chat_session_coordinator.dart';
export '../controllers/chat_summary_controller.dart';
export '../services/tool_ui_renderer_registry.dart';
export 'chat_collection_providers.dart';
export 'chat_dependency_providers.dart';
export 'chat_interaction_providers.dart';
export 'chat_send_state_providers.dart';
export 'chat_ui_providers.dart';

final chatSendCoordinatorProvider = Provider<ChatSendCoordinator>((ref) {
  return DefaultChatSendCoordinator(ref);
});

final chatSessionCoordinatorProvider = Provider<ChatSessionCoordinator>((ref) {
  return DefaultChatSessionCoordinator(ref);
});

final chatSummaryControllerProvider = Provider<ChatSummaryController>((ref) {
  return DefaultChatSummaryController(
    ref,
    sessionCoordinator: ref.read(chatSessionCoordinatorProvider),
  );
});

final chatInteractionCoordinatorProvider =
    Provider<ChatInteractionCoordinator>((ref) {
  return DefaultChatInteractionCoordinator(
    ref,
    sendCoordinator: ref.read(chatSendCoordinatorProvider),
  );
});

final chatPreferencesControllerProvider =
    Provider<ChatPreferencesController>((ref) {
  return DefaultChatPreferencesController(ref);
});

final chatControllerProvider = Provider<ChatController>((ref) {
  return ChatController(
    ref,
    sendCoordinator: ref.read(chatSendCoordinatorProvider),
    sessionCoordinator: ref.read(chatSessionCoordinatorProvider),
    summaryController: ref.read(chatSummaryControllerProvider),
    preferencesController: ref.read(chatPreferencesControllerProvider),
  );
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
      WebSearchToolUiRenderer(),
      FetchWebpageToolUiRenderer(),
    ],
  );
});

CompactToolRowModel _buildReadWorkflowRow(List<ToolWorkflowStep> steps) {
  final latestStep = steps.isEmpty ? null : steps.last;
  final filePath = latestStep == null
      ? ''
      : (latestStep.details['file_path'] ?? '').toString().trim();
  return CompactToolRowModel(
    actionLabel: '读取',
    primaryText: filePath.isEmpty ? '已读取文件' : filePath,
    statusLabel: latestStep == null ? '已提议' : _statusLabelForStep(latestStep),
    statusColor: _statusColorForStep(latestStep),
    isRunning: latestStep?.status == ToolWorkflowStepStatus.running,
  );
}

CompactToolRowModel _buildReadResultRow(ToolResult result) {
  final filePath = (result.data['filePath'] ?? '').toString().trim();
  return CompactToolRowModel(
    actionLabel: '读取',
    primaryText: filePath.isEmpty ? '已读取文件' : filePath,
    statusLabel: result.statusLabel,
    statusColor: _statusColorForResult(result),
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
    statusColor: _statusColorForStep(latestStep),
    isRunning: latestStep?.status == ToolWorkflowStepStatus.running,
  );
}

CompactToolRowModel _buildLsResultRow(ToolResult result) {
  final pathValue = (result.data['path'] ?? '').toString();
  return CompactToolRowModel(
    actionLabel: '列目录',
    primaryText: _compactDirectoryPath(pathValue),
    statusLabel: result.statusLabel,
    statusColor: _statusColorForResult(result),
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
    statusColor: _statusColorForStep(latestStep),
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
    statusColor: _statusColorForResult(result),
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
    statusColor: _statusColorForStep(latestStep),
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
    statusColor: _statusColorForResult(result),
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

Color _statusColorForStep(ToolWorkflowStep? step) {
  switch (step?.status) {
    case ToolWorkflowStepStatus.completed:
      return const Color(0xFF2F7D58);
    case ToolWorkflowStepStatus.failed:
    case ToolWorkflowStepStatus.cancelled:
      return const Color(0xFFD98A34);
    case ToolWorkflowStepStatus.awaitingConfirmation:
    case ToolWorkflowStepStatus.running:
    case ToolWorkflowStepStatus.proposed:
    case null:
      return const Color(0xFF4A90E2);
  }
}

Color _statusColorForResult(ToolResult result) {
  return result.status == ToolExecutionStatus.success
      ? const Color(0xFF2F7D58)
      : const Color(0xFFD98A34);
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
