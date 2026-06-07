import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/services/debug/streaming_turn_timeline_builder.dart';

class StreamingTraceLogAnalysis {
  const StreamingTraceLogAnalysis({
    required this.logPath,
    required this.traces,
    required this.selectedTrace,
  });

  final String logPath;
  final List<StreamingTraceIncidentAnalysis> traces;
  final StreamingTraceIncidentAnalysis? selectedTrace;

  Map<String, dynamic> toJson() {
    return {
      'logPath': logPath,
      'selectedTraceId': selectedTrace?.traceId,
      'traces': traces.map((trace) => trace.toJson()).toList(growable: false),
    };
  }
}

class StreamingTraceIncidentAnalysis {
  const StreamingTraceIncidentAnalysis({
    required this.traceId,
    required this.turnId,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.totalElapsedMs,
    required this.firstVisibleAtMs,
    required this.firstVisibleSource,
    required this.artifactFirstVisibleAtMs,
    required this.finalResponseFirstVisibleAtMs,
    required this.effectiveFirstVisibleAtMs,
    required this.tailWindowMs,
    required this.summarySignals,
    required this.summaryLabel,
    required this.incidentReport,
    required this.timeline,
    required this.finalAnswerSegment,
  });

  final String traceId;
  final String turnId;
  final String status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int totalElapsedMs;
  final int? firstVisibleAtMs;
  final String? firstVisibleSource;
  final int? artifactFirstVisibleAtMs;
  final int? finalResponseFirstVisibleAtMs;
  final int? effectiveFirstVisibleAtMs;
  final int? tailWindowMs;
  final List<String> summarySignals;
  final String summaryLabel;
  final StreamingTraceIncidentReport incidentReport;
  final StreamingTurnTimeline timeline;
  final StreamingTurnTimelineSegment? finalAnswerSegment;

  Map<String, dynamic> toJson() {
    return {
      'traceId': traceId,
      'turnId': turnId,
      'status': status,
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'totalElapsedMs': totalElapsedMs,
      'firstVisibleAtMs': firstVisibleAtMs,
      'firstVisibleSource': firstVisibleSource,
      'artifactFirstVisibleAtMs': artifactFirstVisibleAtMs,
      'finalResponseFirstVisibleAtMs': finalResponseFirstVisibleAtMs,
      'effectiveFirstVisibleAtMs': effectiveFirstVisibleAtMs,
      'tailWindowMs': tailWindowMs,
      'summarySignals': summarySignals,
      'summaryLabel': summaryLabel,
      'incidentReport': incidentReport.toJson(),
      'timeline': {
        'traceId': timeline.traceId,
        'turnId': timeline.turnId,
        'status': timeline.status.name,
        'totalElapsedMs': timeline.totalElapsedMs,
        'currentStatusTitle': timeline.currentStatusTitle,
        'currentStatusDetail': timeline.currentStatusDetail,
        'segments': timeline.segments
            .map(
              (segment) => {
                'id': segment.id,
                'type': segment.type.name,
                'title': segment.title,
                'detail': segment.detail,
                'durationMs': segment.durationMs,
                'modelFirstChunkDelayMs': segment.modelFirstChunkDelayMs,
                'modelStreamingDurationMs': segment.modelStreamingDurationMs,
                'isOngoing': segment.isOngoing,
              },
            )
            .toList(growable: false),
      },
      'finalAnswerSegment': finalAnswerSegment == null
          ? null
          : {
              'id': finalAnswerSegment!.id,
              'durationMs': finalAnswerSegment!.durationMs,
              'modelFirstChunkDelayMs':
                  finalAnswerSegment!.modelFirstChunkDelayMs,
              'modelStreamingDurationMs':
                  finalAnswerSegment!.modelStreamingDurationMs,
            },
    };
  }
}

class StreamingTraceIncidentReport {
  const StreamingTraceIncidentReport({
    required this.headline,
    required this.findings,
  });

  final String headline;
  final List<String> findings;

  Map<String, dynamic> toJson() {
    return {
      'headline': headline,
      'findings': findings,
    };
  }
}

class StreamingTraceLogAnalyzer {
  const StreamingTraceLogAnalyzer();

  static const int _lateVisibleTotalThresholdMs = 3000;
  static const int _lateVisibleTailWindowThresholdMs = 1000;

  StreamingTraceLogAnalysis analyze(
    String content, {
    String logPath = '<memory>',
    String? selectedTraceId,
  }) {
    final builders = <String, _TraceBuilder>{};

    for (final rawLine in content.split('\n')) {
      final entry = _StreamingTraceLogEntry.tryParse(rawLine);
      if (entry == null) {
        continue;
      }
      final traceId = _readString(entry.fields, 'traceId');
      final turnId = _readString(entry.fields, 'turnId');
      if (traceId == null || turnId == null) {
        continue;
      }
      final builder = builders.putIfAbsent(
        traceId,
        () => _TraceBuilder(traceId: traceId, turnId: turnId),
      );
      builder.register(entry);
    }

    final traces = builders.values
        .map((builder) => builder.build())
        .whereType<StreamingTraceIncidentAnalysis>()
        .toList(growable: false)
      ..sort((a, b) {
        final aTime = a.completedAt ?? a.startedAt;
        final bTime = b.completedAt ?? b.startedAt;
        return bTime.compareTo(aTime);
      });

    final selected = selectedTraceId == null
        ? traces.firstOrNull
        : traces.where((trace) => trace.traceId == selectedTraceId).firstOrNull;

    return StreamingTraceLogAnalysis(
      logPath: logPath,
      traces: traces,
      selectedTrace: selected,
    );
  }
}

class _TraceBuilder {
  _TraceBuilder({
    required this.traceId,
    required this.turnId,
  });

  final String traceId;
  final String turnId;
  final List<StreamingTraceEntry> _entries = <StreamingTraceEntry>[];
  StreamingTraceLifecycleStatus status = StreamingTraceLifecycleStatus.running;
  DateTime? takeoverAt;

  void register(_StreamingTraceLogEntry entry) {
    final stageName = _readString(entry.fields, 'stage');
    final lifecycleStatus = _readString(entry.fields, 'lifecycleStatus');
    if (entry.message == 'streaming.trace.lifecycle') {
      if (lifecycleStatus == StreamingTraceLifecycleStatus.completed.name) {
        status = StreamingTraceLifecycleStatus.completed;
      } else if (lifecycleStatus ==
          StreamingTraceLifecycleStatus.aborted.name) {
        status = StreamingTraceLifecycleStatus.aborted;
      }
      final takeoverRaw = _readString(entry.fields, 'takeoverAt');
      if (takeoverRaw != null) {
        takeoverAt = DateTime.tryParse(takeoverRaw) ?? takeoverAt;
      }
      return;
    }
    if (entry.message != 'streaming.trace.stage' || stageName == null) {
      return;
    }
    final stage = StreamingTraceStage.values
        .where((value) => value.name == stageName)
        .firstOrNull;
    if (stage == null) {
      return;
    }
    final startedAt =
        _entries.isEmpty ? entry.timestamp : _entries.first.timestamp;
    final details = Map<String, dynamic>.from(entry.fields)
      ..remove('traceId')
      ..remove('turnId')
      ..remove('stage')
      ..remove('elapsedMsFromStart');
    _entries.add(
      StreamingTraceEntry(
        eventId: '$traceId:${_entries.length}',
        traceId: traceId,
        stage: stage,
        timestamp: entry.timestamp,
        elapsedMsFromStart:
            entry.timestamp.difference(startedAt).inMilliseconds,
        title: stage.name,
        details: details,
      ),
    );
    if (stage == StreamingTraceStage.finalTakeover) {
      takeoverAt = entry.timestamp;
    }
  }

  StreamingTraceIncidentAnalysis? build() {
    if (_entries.isEmpty) {
      return null;
    }
    final sorted = [..._entries]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final startedAt = sorted.first.timestamp;
    final currentStage = sorted.last.stage;
    final uiFirstVisibleEntries = sorted
        .where((entry) => entry.stage == StreamingTraceStage.uiFirstVisible)
        .toList(growable: false);
    final firstVisibleEntry = uiFirstVisibleEntries.firstOrNull;
    final artifactFirstVisibleEntry = uiFirstVisibleEntries
        .where(
          (entry) => _isArtifactPreviewSource(_readVisibilitySource(entry)),
        )
        .firstOrNull;
    final finalResponseFirstVisibleEntry = uiFirstVisibleEntries
        .where(
          (entry) => _readVisibilitySource(entry) == 'final_response_text',
        )
        .firstOrNull;
    final effectiveVisibleEntry = firstVisibleEntry ??
        sorted
            .where((entry) => entry.stage == StreamingTraceStage.finalTakeover)
            .firstOrNull;
    final snapshot = StreamingTraceSnapshot(
      traceId: traceId,
      turnId: turnId,
      status: status,
      currentStage: currentStage,
      summaryText: currentStage.name,
      startedAt: startedAt,
      firstVisibleAt: firstVisibleEntry?.timestamp,
      takeoverAt: takeoverAt,
      entries: List.unmodifiable(sorted),
    );
    final timeline = const StreamingTurnTimelineBuilder().build(
      snapshot,
      now: takeoverAt ?? sorted.last.timestamp,
    );
    final totalElapsedMs = timeline.totalElapsedMs;
    final firstVisibleAtMs =
        firstVisibleEntry?.timestamp.difference(startedAt).inMilliseconds;
    final firstVisibleSource = firstVisibleEntry == null
        ? null
        : _readVisibilitySource(firstVisibleEntry);
    final artifactFirstVisibleAtMs = artifactFirstVisibleEntry?.timestamp
        .difference(startedAt)
        .inMilliseconds;
    final finalResponseFirstVisibleAtMs = finalResponseFirstVisibleEntry
        ?.timestamp
        .difference(startedAt)
        .inMilliseconds;
    final effectiveFirstVisibleAtMs =
        effectiveVisibleEntry?.timestamp.difference(startedAt).inMilliseconds;
    final tailWindowMs = effectiveFirstVisibleAtMs == null
        ? null
        : totalElapsedMs - effectiveFirstVisibleAtMs;
    final finalResponseTailWindowMs = finalResponseFirstVisibleAtMs == null
        ? null
        : totalElapsedMs - finalResponseFirstVisibleAtMs;
    final summarySignals = <String>[];

    if (totalElapsedMs >
        StreamingTraceLogAnalyzer._lateVisibleTotalThresholdMs) {
      summarySignals.add('long_total_stream');
    }
    if (firstVisibleEntry == null && effectiveVisibleEntry != null) {
      summarySignals.add('visible_only_at_takeover');
    }
    if (totalElapsedMs >
            StreamingTraceLogAnalyzer._lateVisibleTotalThresholdMs &&
        tailWindowMs != null &&
        tailWindowMs <=
            StreamingTraceLogAnalyzer._lateVisibleTailWindowThresholdMs) {
      summarySignals.add('first_visible_in_final_second');
    }
    if (totalElapsedMs >
            StreamingTraceLogAnalyzer._lateVisibleTotalThresholdMs &&
        finalResponseTailWindowMs != null &&
        finalResponseTailWindowMs <=
            StreamingTraceLogAnalyzer._lateVisibleTailWindowThresholdMs) {
      summarySignals.add('final_text_visible_in_final_second');
    }

    final summaryLabel = summarySignals.isEmpty
        ? 'normal'
        : summarySignals.contains('first_visible_in_final_second')
            ? 'late_visible_after_long_stream'
            : summarySignals.join(' + ');

    final findings = <String>[];
    if (summarySignals.contains('long_total_stream')) {
      findings.add('Total streamed timeline lasted ${totalElapsedMs}ms.');
    }
    if (artifactFirstVisibleAtMs != null &&
        finalResponseFirstVisibleAtMs != null &&
        artifactFirstVisibleAtMs < finalResponseFirstVisibleAtMs) {
      findings.add(
        'Artifact preview became visible at ${artifactFirstVisibleAtMs}ms before final response text.',
      );
    }
    if (summarySignals.contains('first_visible_in_final_second') &&
        effectiveFirstVisibleAtMs != null &&
        tailWindowMs != null) {
      findings.add(
        'UI first became visible at ${effectiveFirstVisibleAtMs}ms, leaving only ${tailWindowMs}ms before completion.',
      );
    }
    if (summarySignals.contains('final_text_visible_in_final_second') &&
        finalResponseFirstVisibleAtMs != null &&
        finalResponseTailWindowMs != null) {
      findings.add(
        'Final response text first became visible at ${finalResponseFirstVisibleAtMs}ms, leaving only ${finalResponseTailWindowMs}ms before completion.',
      );
    }
    if (summarySignals.contains('visible_only_at_takeover')) {
      findings
          .add('No uiFirstVisible event was observed before final takeover.');
    }

    final finalAnswerSegment = timeline.segments
        .where(
          (segment) =>
              segment.type == StreamingTurnTimelineSegmentType.finalAnswer,
        )
        .lastOrNull;

    return StreamingTraceIncidentAnalysis(
      traceId: traceId,
      turnId: turnId,
      status: status.name,
      startedAt: startedAt,
      completedAt: takeoverAt,
      totalElapsedMs: totalElapsedMs,
      firstVisibleAtMs: firstVisibleAtMs,
      firstVisibleSource: firstVisibleSource,
      artifactFirstVisibleAtMs: artifactFirstVisibleAtMs,
      finalResponseFirstVisibleAtMs: finalResponseFirstVisibleAtMs,
      effectiveFirstVisibleAtMs: effectiveFirstVisibleAtMs,
      tailWindowMs: tailWindowMs,
      summarySignals: List.unmodifiable(summarySignals),
      summaryLabel: summaryLabel,
      incidentReport: StreamingTraceIncidentReport(
        headline: summaryLabel,
        findings: List.unmodifiable(findings),
      ),
      timeline: timeline,
      finalAnswerSegment: finalAnswerSegment,
    );
  }

  String? _readVisibilitySource(StreamingTraceEntry entry) {
    final source = entry.details['source'];
    if (source is! String) {
      return null;
    }
    final trimmed = source.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _isArtifactPreviewSource(String? source) {
    return source == 'artifact_runtime_preview' ||
        source == 'artifact_final_preview';
  }
}

class _StreamingTraceLogEntry {
  const _StreamingTraceLogEntry({
    required this.timestamp,
    required this.message,
    required this.fields,
  });

  final DateTime timestamp;
  final String message;
  final Map<String, String> fields;

  static final RegExp _linePattern = RegExp(
    r'^(\S+)\s+\S+\s+\[trace\]\s+\[StreamingTraceRecorder\]\s+(\S+)(?:\s+(.*))?$',
  );

  static _StreamingTraceLogEntry? tryParse(String line) {
    final match = _linePattern.firstMatch(line.trim());
    if (match == null) {
      return null;
    }
    final timestamp = DateTime.tryParse(match.group(1) ?? '');
    final message = match.group(2);
    if (timestamp == null || message == null) {
      return null;
    }
    return _StreamingTraceLogEntry(
      timestamp: timestamp,
      message: message,
      fields: _parseFields(match.group(3) ?? ''),
    );
  }

  static Map<String, String> _parseFields(String raw) {
    final result = <String, String>{};
    if (raw.trim().isEmpty) {
      return result;
    }

    String? currentKey;
    var valueStart = 0;
    var inQuotes = false;
    var bracketDepth = 0;
    var braceDepth = 0;
    var i = 0;

    bool isKeyStart(int index) {
      if (index < 0 || index >= raw.length) {
        return false;
      }
      if (index > 0 && raw[index - 1] != ' ') {
        return false;
      }
      final first = raw.codeUnitAt(index);
      final isLetter =
          (first >= 65 && first <= 90) || (first >= 97 && first <= 122);
      if (!isLetter) {
        return false;
      }
      var cursor = index + 1;
      while (cursor < raw.length) {
        final code = raw.codeUnitAt(cursor);
        final isAlphaNumeric = (code >= 48 && code <= 57) ||
            (code >= 65 && code <= 90) ||
            (code >= 97 && code <= 122);
        if (!isAlphaNumeric) {
          return raw[cursor] == '=';
        }
        cursor += 1;
      }
      return false;
    }

    while (i < raw.length) {
      final char = raw[i];
      if (char == '"') {
        inQuotes = !inQuotes;
        i += 1;
        continue;
      }
      if (!inQuotes) {
        if (char == '[') {
          bracketDepth += 1;
        } else if (char == ']') {
          bracketDepth = bracketDepth > 0 ? bracketDepth - 1 : 0;
        } else if (char == '{') {
          braceDepth += 1;
        } else if (char == '}') {
          braceDepth = braceDepth > 0 ? braceDepth - 1 : 0;
        }
      }

      if (!inQuotes && bracketDepth == 0 && braceDepth == 0 && isKeyStart(i)) {
        var keyEnd = i + 1;
        while (keyEnd < raw.length && raw[keyEnd] != '=') {
          keyEnd += 1;
        }
        if (keyEnd >= raw.length) {
          break;
        }
        if (currentKey != null) {
          result[currentKey] = raw.substring(valueStart, i).trim();
        }
        currentKey = raw.substring(i, keyEnd);
        valueStart = keyEnd + 1;
        i = valueStart;
        continue;
      }
      i += 1;
    }

    if (currentKey != null && valueStart <= raw.length) {
      result[currentKey] = raw.substring(valueStart).trim();
    }
    return result;
  }
}

String? _readString(Map<String, String> fields, String key) {
  final value = fields[key]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
