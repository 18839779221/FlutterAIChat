import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/debug/debug_cache_panel_projection.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_context_section.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_projection.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_timeline_entry.dart';
import 'package:ai_chat/models/debug/debug_turn_option.dart';
import 'package:ai_chat/models/debug/llm_cache_request_record.dart';
import 'package:ai_chat/models/debug/llm_cache_stats_bucket.dart';
import 'package:ai_chat/models/debug/llm_cache_stats_summary.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/widgets/debug/debug_turn_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('debug inspector restores the last opened tab', (tester) async {
    SharedPreferences.setMockInitialValues({
      'debug.turn_inspector.last_tab_index': 2,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1800,
              child: DebugTurnInspectorSheet(
                groupId: 7,
                initialProjection: _buildProjection(),
                projectionLoader: (groupId, selectedTurnId) async {
                  return _buildProjection();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Context'), findsOneWidget);
    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();
    expect(find.text('core rule line 1\n\nplanner stage line 2\n\nuser prompt line 3'), findsOneWidget);
  });

  testWidgets('debug inspector refresh button reloads projection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var refreshCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1800,
              child: DebugTurnInspectorSheet(
                groupId: 7,
                initialProjection: _buildProjection(
                  status: ChatTurnStatus.running,
                ),
                projectionLoader: (groupId, selectedTurnId) async {
                  refreshCount += 1;
                  return _buildProjection(
                    status: ChatTurnStatus.completed,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('"status": "running"'), findsOneWidget);

    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(refreshCount, 1);
    expect(find.textContaining('"status": "completed"'), findsOneWidget);
  });

  testWidgets('context renders escaped newlines as multiline text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'debug.turn_inspector.last_tab_index': 2,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1800,
              child: DebugTurnInspectorSheet(
                groupId: 7,
                initialProjection: _buildProjection(),
                projectionLoader: (groupId, selectedTurnId) async {
                  return _buildProjection();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();
    expect(
      find.text('core rule line 1\n\nplanner stage line 2\n\nuser prompt line 3'),
      findsOneWidget,
    );
  });

  testWidgets('planner messages support per-item expand and collapse', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'debug.turn_inspector.last_tab_index': 2,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1800,
              child: DebugTurnInspectorSheet(
                groupId: 7,
                initialProjection: _buildProjection(),
                projectionLoader: (groupId, selectedTurnId) async {
                  return _buildProjection();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planner Messages').first);
    await tester.pumpAndSettle();
    expect(find.text('Message 1'), findsOneWidget);
    expect(find.text('Message 2'), findsOneWidget);
    expect(find.text('payloadJson'), findsNothing);

    final message2Tile = find.byKey(
      const PageStorageKey<String>('debug-message-102-1'),
    );
    await tester.ensureVisible(message2Tile);
    final message2TapTarget = find.descendant(
      of: message2Tile,
      matching: find.byType(ListTile),
    );
    await tester.tapAt(tester.getTopLeft(message2TapTarget) + const Offset(24, 24));
    await tester.pumpAndSettle();

    expect(find.byKey(const PageStorageKey<String>('debug-message-102-1')), findsOneWidget);

    await tester.tapAt(tester.getTopLeft(message2TapTarget) + const Offset(24, 24));
    await tester.pumpAndSettle();

    expect(find.byKey(const PageStorageKey<String>('debug-message-102-1')), findsOneWidget);
  });

  testWidgets('context shows static prompt inputs section', (tester) async {
    SharedPreferences.setMockInitialValues({
      'debug.turn_inspector.last_tab_index': 2,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1800,
              child: DebugTurnInspectorSheet(
                groupId: 7,
                initialProjection: _buildProjection(),
                projectionLoader: (groupId, selectedTurnId) async {
                  return _buildProjection();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();
    expect(find.text('toolList'), findsOneWidget);
    expect(find.text('skillList'), findsOneWidget);
  });

  testWidgets('context shows runtime preview summary for streaming response', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'debug.turn_inspector.last_tab_index': 2,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1800,
              child: DebugTurnInspectorSheet(
                groupId: 7,
                initialProjection: _buildProjection(
                  contextSections: const [
                    DebugTurnInspectorContextSection(
                      id: 'runtime-stream',
                      title: 'Runtime Preview State',
                      summary: '1 messages, 2 blocks, text/thinking',
                      defaultExpanded: false,
                      rawJson: {
                        'previewSummary': {
                          'messageCount': 1,
                          'blockCount': 2,
                          'blockTypes': ['text', 'thinking'],
                        },
                        'messages': [
                          {
                            'messageId': 'preview_1',
                            'blocks': [
                              {'blockType': 'text', 'text': 'hello'},
                              {'blockType': 'thinking', 'text': 'plan'},
                            ],
                          },
                        ],
                      },
                    ),
                  ],
                ),
                projectionLoader: (groupId, selectedTurnId) async {
                  return _buildProjection(
                    contextSections: const [
                      DebugTurnInspectorContextSection(
                        id: 'runtime-stream',
                        title: 'Runtime Preview State',
                        summary: '1 messages, 2 blocks, text/thinking',
                        defaultExpanded: false,
                        rawJson: {
                          'previewSummary': {
                            'messageCount': 1,
                            'blockCount': 2,
                            'blockTypes': ['text', 'thinking'],
                          },
                          'messages': [
                            {
                              'messageId': 'preview_1',
                              'blocks': [
                                {'blockType': 'text', 'text': 'hello'},
                                {'blockType': 'thinking', 'text': 'plan'},
                              ],
                            },
                          ],
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();

    expect(find.text('Runtime Preview State'), findsOneWidget);
    expect(find.text('1 messages, 2 blocks, text/thinking'), findsOneWidget);
    expect(find.text('previewSummary'), findsOneWidget);
    expect(find.text('blockTypes'), findsOneWidget);
  });

  testWidgets('cache tab renders summary and recent requests', (tester) async {
    SharedPreferences.setMockInitialValues({
      'debug.turn_inspector.last_tab_index': 3,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1800,
              child: DebugTurnInspectorSheet(
                groupId: 7,
                initialProjection: _buildProjection(),
                projectionLoader: (groupId, selectedTurnId) async {
                  return _buildProjection();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cache'), findsOneWidget);
    expect(find.text('Token Hit Rate'), findsOneWidget);
    expect(find.text('Request Hit Rate'), findsOneWidget);
    expect(find.text('By API Style'), findsOneWidget);
    expect(find.text('Recent Requests'), findsOneWidget);
    expect(find.text('Strategy'), findsOneWidget);
    expect(find.text('Cached'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('responses'), findsWidgets);
    expect(find.textContaining('gpt-5.4'), findsWidgets);
  });

  testWidgets('cache tab renders warning state', (tester) async {
    SharedPreferences.setMockInitialValues({
      'debug.turn_inspector.last_tab_index': 3,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1800,
              child: DebugTurnInspectorSheet(
                groupId: 7,
                initialProjection: _buildProjection(
                  cachePanel: const DebugCachePanelProjection(
                    sampleSize: 100,
                    sourceLogPath: '/tmp/app.log',
                    summary: LlmCacheStatsSummary(
                      totalRequests: 0,
                      requestsWithUsage: 0,
                      hitRequests: 0,
                      totalInputTokens: 0,
                      hitInputTokens: 0,
                    ),
                    bucketsByApiStyle: [],
                    recentRequests: [],
                    warningMessage: '当前平台无本地日志文件',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前平台无本地日志文件'), findsOneWidget);
    expect(find.text('No cache request samples found.'), findsNWidgets(2));
  });

  testWidgets('cache tab uses compact request table on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'debug.turn_inspector.last_tab_index': 3,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 844,
              child: DebugTurnInspectorSheet(
                groupId: 7,
                initialProjection: _buildProjection(),
                projectionLoader: (groupId, selectedTurnId) async {
                  return _buildProjection();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('In'), findsOneWidget);
    expect(find.text('Hit'), findsOneWidget);
    expect(find.text('Ms'), findsOneWidget);
    expect(find.textContaining('responses'), findsWidgets);
    expect(find.textContaining('observeOnly'), findsWidgets);
  });
}

DebugTurnInspectorProjection _buildProjection({
  ChatTurnStatus status = ChatTurnStatus.running,
  DebugCachePanelProjection? cachePanel,
  List<DebugTurnInspectorContextSection>? contextSections,
}) {
  return DebugTurnInspectorProjection(
    turnOptions: [
      DebugTurnOption(
        turnId: 1,
        status: 'running',
        updatedAt: DateTime(2026, 5, 5, 12, 0),
        userInputPreview: 'preview',
      ),
    ],
    selectedTurnId: 1,
    activeTurnOverview: DebugTurnOverview(
      turnId: 1,
      groupId: 7,
      status: status,
      sendPhase: 'planning',
      iterationCount: 1,
      toolCallCount: 0,
      providerStyle: 'responses',
      modelName: 'gpt-5.4',
      diagnosticCode: null,
      errorMessage: null,
      hasRuntimeDraft: false,
      runtimePreviewMessageCount: 0,
      hasPendingConfirmation: false,
      hasActiveQuestion: false,
      startedAt: DateTime(2026, 5, 5, 12, 0),
      updatedAt: DateTime(2026, 5, 5, 12, 1),
      durationMs: 60,
    ),
    timelineEntries: [
      DebugTurnTimelineEntry(
        id: '1',
        timestamp: DateTime(2026, 5, 5, 12, 0),
        kind: 'userMessage',
        title: 'userMessage',
        summary: 'hello',
        source: DebugTurnTimelineSource.persisted,
        severity: DebugTimelineSeverity.info,
      ),
    ],
    contextSections: contextSections ??
        const [
          DebugTurnInspectorContextSection(
            id: 'static-prompt-inputs',
            title: 'Static Prompt Inputs',
            summary: 'system prompt, tools, skills',
            defaultExpanded: false,
            rawJson: {
              'systemPrompt': 'core rule line 1\\n\\nplanner stage line 2\\n\\nuser prompt line 3',
              'toolList': ['create_artifact', 'create_artifact__guideline'],
              'skillList': ['edge-to-edge', 'artifact-authoring'],
            },
          ),
          DebugTurnInspectorContextSection(
            id: 'resolved-system-prompt',
            title: 'Resolved System Prompt',
            summary: 'system prompt preview',
            defaultExpanded: true,
            rawText: 'core rule line 1\\n\\nplanner stage line 2\\n\\nuser prompt line 3',
          ),
          DebugTurnInspectorContextSection(
            id: 'planner-messages',
            title: 'Planner Messages',
            summary: '2 items',
            defaultExpanded: true,
            rawJson: {
              'messages': [
                {
                  'id': 101,
                  'role': 'system',
                  'status': 'completed',
                  'timestamp': '2026-05-05T12:00:00.000',
                  'text': 'line1\\nline2\\nline3',
                },
                {
                  'id': 102,
                  'role': 'user',
                  'status': 'completed',
                  'timestamp': '2026-05-05T12:00:10.000',
                  'text': 'second line A\\nsecond line B',
                  'payloadJson': {
                    'prompt': 'alpha\\nbeta',
                  },
                },
              ],
            },
          ),
          DebugTurnInspectorContextSection(
            id: 'transcript-events',
            title: 'Transcript Events',
            summary: '1 items',
            defaultExpanded: false,
            rawJson: {'events': []},
          ),
          DebugTurnInspectorContextSection(
            id: 'provider-state',
            title: 'Provider State',
            summary: '1 items',
            defaultExpanded: false,
            rawJson: {'state': []},
          ),
          DebugTurnInspectorContextSection(
            id: 'runtime-stream',
            title: 'Runtime Stream Entries',
            summary: '0 items',
            defaultExpanded: false,
            rawJson: {'entries': []},
          ),
          DebugTurnInspectorContextSection(
            id: 'trace-events',
            title: 'Trace Events',
            summary: '0 items',
            defaultExpanded: false,
            rawJson: {'events': []},
          ),
          DebugTurnInspectorContextSection(
            id: 'runtime-draft',
            title: 'Runtime Draft',
            summary: 'null',
            defaultExpanded: false,
            rawJson: {'draft': null},
          ),
          DebugTurnInspectorContextSection(
            id: 'active-question',
            title: 'Active Question',
            summary: 'null',
            defaultExpanded: false,
            rawJson: {'question': null},
          ),
        ],
    cachePanel: cachePanel ??
        DebugCachePanelProjection(
          sampleSize: 100,
          sourceLogPath: '/tmp/app.log',
          summary: const LlmCacheStatsSummary(
            totalRequests: 3,
            requestsWithUsage: 3,
            hitRequests: 2,
            totalInputTokens: 200,
            hitInputTokens: 120,
          ),
          bucketsByApiStyle: const [
            LlmCacheStatsBucket(
              key: 'responses',
              summary: LlmCacheStatsSummary(
                totalRequests: 2,
                requestsWithUsage: 2,
                hitRequests: 1,
                totalInputTokens: 140,
                hitInputTokens: 60,
              ),
            ),
            LlmCacheStatsBucket(
              key: 'chatCompletions',
              summary: LlmCacheStatsSummary(
                totalRequests: 1,
                requestsWithUsage: 1,
                hitRequests: 1,
                totalInputTokens: 60,
                hitInputTokens: 60,
              ),
            ),
          ],
          recentRequests: [
            LlmCacheRequestRecord(
              timestamp: DateTime(2026, 5, 5, 12, 2),
              apiStyle: 'responses',
              modelName: 'gpt-5.4',
              purpose: 'planner',
              cacheStrategy: 'observeOnly',
              inputTokens: 100,
              estimatedInputTokens: 120,
              cachedInputTokens: 60,
              totalMs: 900,
              firstChunkMs: 300,
            ),
          ],
        ),
  );
}
