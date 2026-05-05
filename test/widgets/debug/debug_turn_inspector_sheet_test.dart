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
    expect(find.text('Runtime Stream Entries'), findsOneWidget);
    expect(
      find.textContaining('"entries": []'),
      findsOneWidget,
    );
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
        id: 'planner-messages',
        title: 'Planner Messages',
        summary: '1 items',
        defaultExpanded: true,
        rawJson: {'messages': []},
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
