import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/debug/debug_turn_inspector_context_section.dart';
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
  final Set<String> _expandedMessageIds = <String>{};

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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextSectionBody({
    required ThemeData theme,
    required DebugTurnInspectorContextSection section,
  }) {
    final rawJson = section.rawJson;
    if (rawJson is Map<String, dynamic>) {
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
