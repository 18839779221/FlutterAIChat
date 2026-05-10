import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_context_section.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_projection.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_timeline_entry.dart';
import 'package:ai_chat/models/debug/debug_turn_option.dart';
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
              height: 640,
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
    expect(find.text('Resolved System Prompt'), findsOneWidget);
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
              height: 640,
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
              height: 640,
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

    expect(find.text('line1\nline2\nline3'), findsWidgets);
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
              height: 700,
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
}

DebugTurnInspectorProjection _buildProjection({
  ChatTurnStatus status = ChatTurnStatus.running,
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
      runtimeStreamEntryCount: 0,
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
    contextSections: const [
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
  );
}
