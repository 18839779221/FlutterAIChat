import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/debug/debug_turn_inspector_projection.dart';
import 'package:ai_chat/providers/debug_turn_inspector_providers.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/debug/debug_turn_inspector_projection_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DebugTurnInspectorSheet extends ConsumerStatefulWidget {
  const DebugTurnInspectorSheet({
    super.key,
    required this.groupId,
    required this.initialProjection,
    this.projectionLoader,
  });

  final int groupId;
  final DebugTurnInspectorProjection initialProjection;
  final Future<DebugTurnInspectorProjection> Function(
    int groupId,
    int? selectedTurnId,
  )? projectionLoader;

  @override
  ConsumerState<DebugTurnInspectorSheet> createState() =>
      _DebugTurnInspectorSheetState();
}

class _DebugTurnInspectorSheetState extends ConsumerState<DebugTurnInspectorSheet>
    with SingleTickerProviderStateMixin {
  late DebugTurnInspectorProjection _projection = widget.initialProjection;
  late final TabController _tabController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    final savedIndex = ref
        .read(debugTurnInspectorPreferencesProvider)
        .getLastTabIndex();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: savedIndex.clamp(0, 2),
    );
    _tabController.addListener(_persistTabIndex);
  }

  @override
  void dispose() {
    _tabController.removeListener(_persistTabIndex);
    _tabController.dispose();
    super.dispose();
  }

  void _persistTabIndex() {
    if (_tabController.indexIsChanging) {
      return;
    }
    unawaited(
      ref
          .read(debugTurnInspectorPreferencesProvider)
          .setLastTabIndex(_tabController.index),
    );
  }

  Future<void> _refresh() async {
    if (_isRefreshing) {
      return;
    }
    setState(() {
      _isRefreshing = true;
    });
    try {
      final refreshed = await _loadProjection(
        groupId: widget.groupId,
        selectedTurnId: null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _projection = refreshed;
      });
      unawaited(
        ref
            .read(debugTurnInspectorPreferencesProvider)
            .setLastTabIndex(_tabController.index),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _changeTurn(int? turnId) {
    if (turnId == null || turnId == _projection.selectedTurnId) {
      return;
    }
    setState(() {
      _projection = _projection.copyWithSelectedTurn(turnId);
    });
    unawaited(_refreshSelectedTurn(turnId));
  }

  Future<void> _refreshSelectedTurn(int turnId) async {
    final refreshed = await _loadProjection(
      groupId: widget.groupId,
      selectedTurnId: turnId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _projection = refreshed;
    });
  }

  Future<DebugTurnInspectorProjection> _loadProjection({
    required int groupId,
    required int? selectedTurnId,
  }) async {
    final loader = widget.projectionLoader;
    if (loader != null) {
      return loader(groupId, selectedTurnId);
    }
    final service = DebugTurnInspectorProjectionService(
      chatTurnRepository: ref.read(chatTurnRepositoryProvider),
      chatEventRepository: ref.read(chatEventRepositoryProvider),
      sessionContextService: ref.read(sessionContextServiceProvider),
      traceRecorder: ref.read(traceRecorderProvider),
      runtimeAssistantDraft: ref.read(runtimeAssistantDraftProvider),
      runtimeStreamEntries: ref.read(runtimeStreamEntriesProvider),
      toolPresentationEvents:
          ref.read(chatTimelineProjectionProvider).toolPresentationEvents,
      sendPhase: ref.read(chatSendStateProvider).phase,
      sendStatusText: ref.read(chatSendStateProvider).statusText,
      activeAskUserQuestionMessage:
          ref.read(activeAskUserQuestionMessageProvider),
    );
    return service.build(
      groupId: groupId,
      selectedTurnId: selectedTurnId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overview = _projection.activeTurnOverview;
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Debug Turn Inspector',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _isRefreshing ? null : _refresh,
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
                if (_projection.turnOptions.isNotEmpty)
                  DropdownButton<int>(
                    value: _projection.selectedTurnId,
                    items: _projection.turnOptions
                        .map(
                          (turn) => DropdownMenuItem<int>(
                            value: turn.turnId,
                            child: Text('#${turn.turnId} ${turn.status}'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _changeTurn,
                  ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Timeline'),
              Tab(text: 'Context'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert({
                        'turnId': overview?.turnId,
                        'groupId': overview?.groupId,
                        'status': overview?.status.name,
                        'sendPhase': overview?.sendPhase,
                        'iterationCount': overview?.iterationCount,
                        'toolCallCount': overview?.toolCallCount,
                        'providerStyle': overview?.providerStyle,
                        'modelName': overview?.modelName,
                        'diagnosticCode': overview?.diagnosticCode,
                        'errorMessage': overview?.errorMessage,
                        'hasRuntimeDraft': overview?.hasRuntimeDraft,
                        'runtimeStreamEntryCount':
                            overview?.runtimeStreamEntryCount,
                        'hasPendingConfirmation':
                            overview?.hasPendingConfirmation,
                        'hasActiveQuestion': overview?.hasActiveQuestion,
                        'durationMs': overview?.durationMs,
                      }),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'JetBrainsMono',
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert(
                        _projection.timelineEntries
                            .map(
                              (item) => {
                                'id': item.id,
                                'timestamp': item.timestamp.toIso8601String(),
                                'kind': item.kind,
                                'title': item.title,
                                'summary': item.summary,
                                'source': item.source.name,
                                'severity': item.severity.name,
                                'payloadJson': item.payloadJson,
                              },
                            )
                            .toList(growable: false),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'JetBrainsMono',
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: _projection.contextSections
                      .map(
                        (section) => Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                section.title,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                section.summary,
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 10),
                              SelectableText(
                                section.rawJson == null
                                    ? (section.rawText ?? 'null')
                                    : const JsonEncoder.withIndent('  ')
                                        .convert(section.rawJson),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'JetBrainsMono',
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
