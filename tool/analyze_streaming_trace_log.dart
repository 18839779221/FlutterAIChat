import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/services/debug/streaming_trace_log_analyzer.dart';

void main(List<String> args) async {
  final parsed = _CliArguments.parse(args);
  if (parsed.showHelp) {
    stdout.writeln(_usage);
    return;
  }

  if (parsed.logPath == null) {
    stderr.writeln('Missing log path.\n');
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  final file = File(parsed.logPath!);
  if (!await file.exists()) {
    stderr.writeln('Log file not found: ${parsed.logPath}');
    exitCode = 66;
    return;
  }

  const analyzer = StreamingTraceLogAnalyzer();
  final analysis = analyzer.analyze(
    await file.readAsString(),
    logPath: file.path,
    selectedTraceId: parsed.traceId,
  );

  if (parsed.asJson) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(analysis.toJson()),
    );
    return;
  }

  if (parsed.asReport) {
    stdout.writeln(
        _formatIncidentReport(analysis, requestedTraceId: parsed.traceId));
    if (analysis.selectedTrace == null) {
      exitCode = 1;
    }
    return;
  }

  stdout
      .writeln(_formatHumanReport(analysis, requestedTraceId: parsed.traceId));
  if (analysis.selectedTrace == null) {
    exitCode = 1;
  }
}

String _formatHumanReport(
  StreamingTraceLogAnalysis analysis, {
  String? requestedTraceId,
}) {
  final buffer = StringBuffer()
    ..writeln('Log: ${analysis.logPath}')
    ..writeln('Traces: ${analysis.traces.length}');

  final selected = analysis.selectedTrace;
  if (selected == null) {
    if (requestedTraceId != null) {
      buffer.writeln('Selected trace: missing ($requestedTraceId)');
    } else {
      buffer.writeln('Selected trace: none');
    }
    if (analysis.traces.isEmpty) {
      buffer.writeln(
        'No persisted streaming trace events found. Reinstall the updated build and reproduce once.',
      );
    }
    if (analysis.traces.isNotEmpty) {
      buffer.writeln('Available traces:');
      for (final trace in analysis.traces) {
        buffer.writeln('- ${trace.traceId}');
      }
    }
    return buffer.toString().trimRight();
  }

  buffer
    ..writeln('Selected trace: ${selected.traceId}')
    ..writeln('Turn: ${selected.turnId}')
    ..writeln(
      'Window: ${selected.startedAt.toIso8601String()} -> ${selected.completedAt?.toIso8601String() ?? '-'}',
    )
    ..writeln(
      'Status: ${selected.status}'
      ' | totalElapsedMs: ${selected.totalElapsedMs}'
      ' | firstVisibleAtMs: ${selected.firstVisibleAtMs ?? '-'}'
      ' | firstVisibleSource: ${selected.firstVisibleSource ?? '-'}'
      ' | artifactFirstVisibleAtMs: ${selected.artifactFirstVisibleAtMs ?? '-'}'
      ' | finalResponseFirstVisibleAtMs: ${selected.finalResponseFirstVisibleAtMs ?? '-'}'
      ' | effectiveFirstVisibleAtMs: ${selected.effectiveFirstVisibleAtMs ?? '-'}'
      ' | tailWindowMs: ${selected.tailWindowMs ?? '-'}',
    )
    ..writeln(
      'Summary: ${selected.summaryLabel}'
      ' | signals=${selected.summarySignals.isEmpty ? '[]' : selected.summarySignals.join(', ')}',
    );

  final finalAnswer = selected.finalAnswerSegment;
  if (finalAnswer != null) {
    buffer.writeln(
      'Final answer segment: durationMs=${finalAnswer.durationMs}'
      ' | firstChunkDelayMs=${finalAnswer.modelFirstChunkDelayMs ?? '-'}'
      ' | streamingDurationMs=${finalAnswer.modelStreamingDurationMs ?? '-'}',
    );
  }

  buffer.writeln('Timeline segments:');
  for (final segment in selected.timeline.segments) {
    buffer.writeln(
      '- ${segment.type.name}'
      ' title=${segment.title}'
      ' durationMs=${segment.durationMs}'
      ' firstChunkDelayMs=${segment.modelFirstChunkDelayMs ?? '-'}'
      ' streamingDurationMs=${segment.modelStreamingDurationMs ?? '-'}'
      '${segment.isOngoing ? ' ongoing=true' : ''}',
    );
  }

  if (analysis.traces.length > 1) {
    buffer.writeln('Other traces:');
    for (final trace in analysis.traces.skip(1)) {
      buffer.writeln(
        '- ${trace.traceId} totalElapsedMs=${trace.totalElapsedMs} signals=${trace.summarySignals.join(',')}',
      );
    }
  }

  return buffer.toString().trimRight();
}

String _formatIncidentReport(
  StreamingTraceLogAnalysis analysis, {
  String? requestedTraceId,
}) {
  final selected = analysis.selectedTrace;
  if (selected == null) {
    if (requestedTraceId != null) {
      return 'Timeline incident report unavailable: missing trace ($requestedTraceId)';
    }
    if (analysis.traces.isEmpty) {
      return 'Timeline incident report unavailable: no persisted streaming trace events found in this log';
    }
    return 'Timeline incident report unavailable: no trace selected';
  }

  final report = selected.incidentReport;
  final buffer = StringBuffer()
    ..writeln('Streaming timeline incident report')
    ..writeln('Trace: ${selected.traceId}')
    ..writeln('Turn: ${selected.turnId}')
    ..writeln('Headline: ${report.headline}')
    ..writeln(
      'Summary signals: ${selected.summarySignals.isEmpty ? '[]' : selected.summarySignals.join(', ')}',
    )
    ..writeln(
      'Totals: elapsedMs=${selected.totalElapsedMs}'
      ' firstVisibleAtMs=${selected.firstVisibleAtMs ?? '-'}'
      ' firstVisibleSource=${selected.firstVisibleSource ?? '-'}'
      ' artifactFirstVisibleAtMs=${selected.artifactFirstVisibleAtMs ?? '-'}'
      ' finalResponseFirstVisibleAtMs=${selected.finalResponseFirstVisibleAtMs ?? '-'}'
      ' effectiveFirstVisibleAtMs=${selected.effectiveFirstVisibleAtMs ?? '-'}'
      ' tailWindowMs=${selected.tailWindowMs ?? '-'}',
    );

  if (report.findings.isNotEmpty) {
    buffer.writeln('Findings:');
    for (final finding in report.findings) {
      buffer.writeln('- $finding');
    }
  } else {
    buffer.writeln('Findings: none');
  }

  final finalAnswer = selected.finalAnswerSegment;
  if (finalAnswer != null) {
    buffer
      ..writeln('Final answer segment:')
      ..writeln(
        '- durationMs=${finalAnswer.durationMs}'
        ' firstChunkDelayMs=${finalAnswer.modelFirstChunkDelayMs ?? '-'}'
        ' streamingDurationMs=${finalAnswer.modelStreamingDurationMs ?? '-'}',
      );
  }

  return buffer.toString().trimRight();
}

class _CliArguments {
  const _CliArguments({
    required this.logPath,
    required this.traceId,
    required this.asJson,
    required this.asReport,
    required this.showHelp,
  });

  final String? logPath;
  final String? traceId;
  final bool asJson;
  final bool asReport;
  final bool showHelp;

  static _CliArguments parse(List<String> args) {
    String? logPath;
    String? traceId;
    var asJson = false;
    var asReport = false;
    var showHelp = false;

    for (var i = 0; i < args.length; i += 1) {
      final arg = args[i];
      switch (arg) {
        case '--help':
        case '-h':
          showHelp = true;
          break;
        case '--json':
          asJson = true;
          break;
        case '--report':
          asReport = true;
          break;
        case '--trace-id':
          if (i + 1 >= args.length) {
            showHelp = true;
            break;
          }
          traceId = args[i + 1];
          i += 1;
          break;
        default:
          logPath ??= arg;
          break;
      }
    }

    return _CliArguments(
      logPath: logPath,
      traceId: traceId,
      asJson: asJson,
      asReport: asReport,
      showHelp: showHelp,
    );
  }
}

const String _usage = '''
Usage:
  dart run tool/analyze_streaming_trace_log.dart <log_path> [--trace-id <traceId>] [--json] [--report]

Examples:
  dart run tool/analyze_streaming_trace_log.dart build/artifact-debug/latest.log
  dart run tool/analyze_streaming_trace_log.dart build/artifact-debug/latest.log --trace-id turn_96_stream
  dart run tool/analyze_streaming_trace_log.dart build/artifact-debug/latest.log --report
''';
