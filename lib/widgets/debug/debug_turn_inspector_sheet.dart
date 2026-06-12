import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/debug/debug_cache_panel_projection.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_context_section.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_projection.dart';
import 'package:ai_chat/models/debug/llm_cache_request_record.dart';
import 'package:ai_chat/models/debug/llm_cache_stats_bucket.dart';
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
  final Set<String> _expandedMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    final savedIndex = ref
        .read(debugTurnInspectorPreferencesProvider)
        .getLastTabIndex();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: savedIndex.clamp(0, 3),
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
      runtimePreviewState: ref.read(runtimeStreamingPreviewStateProvider),
      toolPresentationEvents:
          ref.read(chatTimelineProjectionProvider).toolPresentationEvents,
      sendPhase: ref.read(chatSendStateProvider).phase,
      activeAskUserQuestionMessage:
          ref.read(activeAskUserQuestionMessageProvider),
      currentGroup: ref.read(currentGroupProvider),
      systemPromptOverride: ref.read(systemPromptProvider),
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
    return Column(
      children: [
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
            Tab(text: 'Cache'),
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
                        'runtimePreviewMessageCount':
                            overview?.runtimePreviewMessageCount,
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
                              _buildContextSectionBody(
                                theme: theme,
                                section: section,
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                _buildCacheTab(
                  theme: theme,
                  cachePanel: _projection.cachePanel,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContextSectionBody({
    required ThemeData theme,
    required DebugTurnInspectorContextSection section,
  }) {
    final rawJson = section.rawJson;
    if (rawJson is Map<String, dynamic>) {
      if (section.id == 'runtime-stream') {
        return _buildRuntimePreviewSection(
          theme: theme,
          rawJson: rawJson,
        );
      }
      final messages = rawJson['messages'];
      if (messages is List) {
        return _buildMessagesSection(
          theme: theme,
          messages: messages,
        );
      }
    }

    if (rawJson != null) {
      return _buildStructuredValue(
        theme: theme,
        value: rawJson,
      );
    }

    return _buildDecodedTextBlock(
      theme: theme,
      text: section.rawText ?? 'null',
    );
  }

  Widget _buildRuntimePreviewSection({
    required ThemeData theme,
    required Map<String, dynamic> rawJson,
  }) {
    final messages = rawJson['messages'];
    final previewSummary = rawJson['previewSummary'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (previewSummary != null) ...[
          _buildLabeledValue(
            theme: theme,
            label: 'previewSummary',
            value: previewSummary,
          ),
          const SizedBox(height: 10),
        ],
        if (messages is List)
          _buildLabeledValue(
            theme: theme,
            label: 'messages',
            value: messages,
          )
        else
          _buildStructuredValue(
            theme: theme,
            value: rawJson,
          ),
      ],
    );
  }

  Widget _buildCacheTab({
    required ThemeData theme,
    required DebugCachePanelProjection? cachePanel,
  }) {
    if (cachePanel == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'No cache request samples found.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if ((cachePanel.warningMessage ?? '').trim().isNotEmpty) ...[
          _buildDebugSectionCard(
            theme: theme,
            title: 'Warning',
            child: Text(
              cachePanel.warningMessage!,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
        ],
        _buildDebugSectionCard(
          theme: theme,
          title: 'Summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetricLine(
                theme: theme,
                label: 'Token Hit Rate',
                value: _formatPercent(cachePanel.summary.tokenHitRate),
              ),
              _buildMetricLine(
                theme: theme,
                label: 'Request Hit Rate',
                value: _formatPercent(cachePanel.summary.requestHitRate),
              ),
              _buildMetricLine(
                theme: theme,
                label: 'Requests',
                value: '${cachePanel.summary.totalRequests}',
              ),
              _buildMetricLine(
                theme: theme,
                label: 'Requests With Usage',
                value: '${cachePanel.summary.requestsWithUsage}',
              ),
              _buildMetricLine(
                theme: theme,
                label: 'Hit Input Tokens / Total Input Tokens',
                value:
                    '${cachePanel.summary.hitInputTokens} / ${cachePanel.summary.totalInputTokens}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildDebugSectionCard(
          theme: theme,
          title: 'By API Style',
          child: cachePanel.bucketsByApiStyle.isEmpty
              ? Text(
                  'No cache request samples found.',
                  style: theme.textTheme.bodySmall,
                )
              : Column(
                  children: cachePanel.bucketsByApiStyle
                      .map(
                        (bucket) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildApiStyleBucket(
                            theme: theme,
                            bucket: bucket,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 16),
        _buildDebugSectionCard(
          theme: theme,
          title: 'Recent Requests',
          child: cachePanel.recentRequests.isEmpty
              ? Text(
                  'No cache request samples found.',
                  style: theme.textTheme.bodySmall,
                )
              : _buildRecentRequestsTable(
                  theme: theme,
                  requests: cachePanel.recentRequests,
                ),
        ),
      ],
    );
  }

  Widget _buildDebugSectionCard({
    required ThemeData theme,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildMetricLine({
    required ThemeData theme,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiStyleBucket({
    required ThemeData theme,
    required LlmCacheStatsBucket bucket,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          bucket.key,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Token Hit Rate: ${_formatPercent(bucket.summary.tokenHitRate)}',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          'Request Hit Rate: ${_formatPercent(bucket.summary.requestHitRate)}',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          'Requests: ${bucket.summary.totalRequests}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildRecentRequestsTable({
    required ThemeData theme,
    required List<LlmCacheRequestRecord> requests,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return _buildCompactRecentRequestsTable(
            theme: theme,
            requests: requests,
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 56,
            dataRowMaxHeight: 72,
            columns: const [
              DataColumn(label: Text('Time')),
              DataColumn(label: Text('API')),
              DataColumn(label: Text('Model')),
              DataColumn(label: Text('Strategy')),
              DataColumn(label: Text('Input')),
              DataColumn(label: Text('Hit')),
              DataColumn(label: Text('Cached')),
              DataColumn(label: Text('Read')),
              DataColumn(label: Text('Miss')),
              DataColumn(label: Text('TotalMs')),
            ],
            rows: requests.map((request) {
              final hitTokens =
                  (request.cachedInputTokens ?? 0) +
                  (request.cacheReadInputTokens ?? 0);
              final inputValue =
                  request.inputTokens ?? request.estimatedInputTokens;
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      _formatShortTimestamp(request.timestamp),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  DataCell(
                    Text(request.apiStyle ?? '-', style: theme.textTheme.bodySmall),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        request.modelName ?? '-',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      request.cacheStrategy ?? '-',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  DataCell(
                    Text('$inputValue', style: theme.textTheme.bodySmall),
                  ),
                  DataCell(Text('$hitTokens', style: theme.textTheme.bodySmall)),
                  DataCell(
                    Text(
                      '${request.cachedInputTokens ?? '-'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  DataCell(
                    Text(
                      '${request.cacheReadInputTokens ?? '-'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  DataCell(
                    Text(
                      '${request.cacheMissInputTokens ?? '-'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  DataCell(
                    Text('${request.totalMs ?? '-'}', style: theme.textTheme.bodySmall),
                  ),
                ],
              );
            }).toList(growable: false),
          ),
        );
      },
    );
  }

  Widget _buildCompactRecentRequestsTable({
    required ThemeData theme,
    required List<LlmCacheRequestRecord> requests,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(child: Text('Time', style: theme.textTheme.labelSmall)),
              SizedBox(
                width: 52,
                child: Text('In', style: theme.textTheme.labelSmall),
              ),
              SizedBox(
                width: 52,
                child: Text('Hit', style: theme.textTheme.labelSmall),
              ),
              SizedBox(
                width: 52,
                child: Text('Ms', style: theme.textTheme.labelSmall),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...requests.map((request) {
          final hitTokens =
              (request.cachedInputTokens ?? 0) +
              (request.cacheReadInputTokens ?? 0);
          final inputValue = request.inputTokens ?? request.estimatedInputTokens;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatShortTimestamp(request.timestamp),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${inputValue ?? '-'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '$hitTokens',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${request.totalMs ?? '-'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${request.apiStyle ?? '-'} · ${request.modelName ?? '-'}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'strategy=${request.cacheStrategy ?? '-'} cached=${request.cachedInputTokens ?? '-'} read=${request.cacheReadInputTokens ?? '-'} miss=${request.cacheMissInputTokens ?? '-'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _formatShortTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute:$second';
  }

  String _formatPercent(double value) {
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  Widget _buildMessagesSection({
    required ThemeData theme,
    required List<dynamic> messages,
  }) {
    if (messages.isEmpty) {
      return _buildDecodedTextBlock(
        theme: theme,
        text: '[]',
      );
    }

    return Column(
      children: List<Widget>.generate(messages.length, (index) {
        final message = messages[index];
        final item = message is Map ? message.cast<String, dynamic>() : null;
        final messageId = item?['id']?.toString() ?? 'message-$index';
        final role = item?['role']?.toString() ?? 'unknown';
        final status = item?['status']?.toString() ?? 'unknown';
        final timestamp = item?['timestamp']?.toString();
        final preview = _previewMultiline(
          _decodeEscapedText(item?['text']?.toString() ?? ''),
        );
        final title = 'Message ${index + 1}';
        final subtitleParts = <String>[role, status];
        if (timestamp != null && timestamp.isNotEmpty) {
          subtitleParts.add(timestamp);
        }
        final tileKey = '$messageId-$index';
        final isExpanded = _expandedMessageIds.contains(tileKey) || index == 0;

        return Container(
          margin: EdgeInsets.only(bottom: index == messages.length - 1 ? 0 : 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.35,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ExpansionTile(
            key: PageStorageKey<String>('debug-message-$tileKey'),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                if (expanded) {
                  _expandedMessageIds.add(tileKey);
                } else {
                  _expandedMessageIds.remove(tileKey);
                }
              });
            },
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              title,
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  subtitleParts.join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ],
              ],
            ),
            children: [
              _buildMessageDetails(
                theme: theme,
                message: item ?? <String, dynamic>{'value': message},
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildMessageDetails({
    required ThemeData theme,
    required Map<String, dynamic> message,
  }) {
    final detailEntries = <MapEntry<String, dynamic>>[
      if (message['role'] != null) MapEntry('role', message['role']),
      if (message['status'] != null) MapEntry('status', message['status']),
      if (message['timestamp'] != null) MapEntry('timestamp', message['timestamp']),
      if (message['text'] != null) MapEntry('text', message['text']),
      if (message['reasoningContent'] != null)
        MapEntry('reasoningContent', message['reasoningContent']),
      if (message['payloadJson'] != null) MapEntry('payloadJson', message['payloadJson']),
      if (message['referenceJson'] != null)
        MapEntry('referenceJson', message['referenceJson']),
      ...message.entries.where(
        (entry) => !{
          'id',
          'role',
          'status',
          'timestamp',
          'text',
          'reasoningContent',
          'payloadJson',
          'referenceJson',
        }.contains(entry.key),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: detailEntries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _buildLabeledValue(
            theme: theme,
            label: entry.key,
            value: entry.value,
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildStructuredValue({
    required ThemeData theme,
    required Object? value,
    int depth = 0,
  }) {
    if (value is Map) {
      final entries = value.entries.toList(growable: false);
      if (entries.isEmpty) {
        return _buildDecodedTextBlock(theme: theme, text: '{}');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries.map((entry) {
          return Padding(
            padding: EdgeInsets.only(bottom: 10, left: depth * 12),
            child: _buildLabeledValue(
              theme: theme,
              label: entry.key.toString(),
              value: entry.value,
              depth: depth,
            ),
          );
        }).toList(growable: false),
      );
    }

    if (value is List) {
      if (value.isEmpty) {
        return _buildDecodedTextBlock(theme: theme, text: '[]');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List<Widget>.generate(value.length, (index) {
          return Padding(
            padding: EdgeInsets.only(bottom: 10, left: depth * 12),
            child: _buildLabeledValue(
              theme: theme,
              label: '[$index]',
              value: value[index],
              depth: depth,
            ),
          );
        }),
      );
    }

    if (value is String) {
      return _buildDecodedTextBlock(
        theme: theme,
        text: value,
      );
    }

    return _buildDecodedTextBlock(
      theme: theme,
      text: value == null ? 'null' : const JsonEncoder.withIndent('  ').convert(value),
    );
  }

  Widget _buildLabeledValue({
    required ThemeData theme,
    required String label,
    required Object? value,
    int depth = 0,
  }) {
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontFamily: 'JetBrainsMono',
      color: theme.colorScheme.primary,
    );

    if (value is Map || value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 6),
          _buildStructuredValue(
            theme: theme,
            value: value,
            depth: depth + 1,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 4),
        _buildDecodedTextBlock(
          theme: theme,
          text: value?.toString() ?? 'null',
        ),
      ],
    );
  }

  Widget _buildDecodedTextBlock({
    required ThemeData theme,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _decodeEscapedText(text),
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'JetBrainsMono',
          height: 1.5,
        ),
      ),
    );
  }

  String _decodeEscapedText(String value) {
    if (value.isEmpty) {
      return value;
    }

    final withUnicode = value.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (match) {
        final codePoint = int.tryParse(match.group(1)!, radix: 16);
        return codePoint == null ? match.group(0)! : String.fromCharCode(codePoint);
      },
    );

    return withUnicode
        .replaceAll(r'\r\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\\', '\\');
  }

  String _previewMultiline(String value) {
    final normalized = value
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
    if (normalized.length <= 180) {
      return normalized;
    }
    return '${normalized.substring(0, 180)}...';
  }
}
