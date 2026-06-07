import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/services/artifact/artifact_render_log_analyzer.dart';

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

  const analyzer = ArtifactRenderLogAnalyzer();
  final analysis = analyzer.analyze(
    await file.readAsString(),
    logPath: file.path,
    selectedFlowId: parsed.flowId,
  );

  if (parsed.asJson) {
    stdout
        .writeln(const JsonEncoder.withIndent('  ').convert(analysis.toJson()));
    return;
  }

  if (parsed.asReport) {
    stdout.writeln(_formatIncidentReport(analysis, requestedFlowId: parsed.flowId));
    if (analysis.selectedFlow == null) {
      exitCode = 1;
    }
    return;
  }

  stdout.writeln(_formatHumanReport(analysis, requestedFlowId: parsed.flowId));
  if (analysis.selectedFlow == null) {
    exitCode = 1;
  }
}

String _formatHumanReport(
  ArtifactRenderLogAnalysis analysis, {
  String? requestedFlowId,
}) {
  final buffer = StringBuffer()
    ..writeln('Log: ${analysis.logPath}')
    ..writeln('Flows: ${analysis.flows.length}');

  final selectedFlow = analysis.selectedFlow;
  if (selectedFlow == null) {
    if (requestedFlowId != null) {
      buffer.writeln('Selected flow: missing ($requestedFlowId)');
    } else {
      buffer.writeln('Selected flow: none');
    }
    if (analysis.flows.isNotEmpty) {
      buffer.writeln('Available flows:');
      for (final flow in analysis.flows) {
        buffer.writeln('- ${flow.flowId}');
      }
    }
    return buffer.toString().trimRight();
  }

  buffer
    ..writeln('Selected flow: ${selectedFlow.flowId}')
    ..writeln(
      'Flow source: ${selectedFlow.usedDerivedFlowId ? 'derived fallback' : 'explicit flowId'}',
    )
    ..writeln(
      'Window: ${selectedFlow.firstEventAt.toIso8601String()} -> ${selectedFlow.lastEventAt.toIso8601String()}',
    )
    ..writeln(
      'Artifact: ${selectedFlow.artifactId ?? '-'}'
      ' | turnId: ${selectedFlow.turnId ?? '-'}'
      ' | providerCallId: ${selectedFlow.providerCallId ?? '-'}',
    )
    ..writeln(
      'Attempts: ${selectedFlow.renderAttemptCount}'
      ' | unique sessionIds: ${selectedFlow.uniqueSessionIdCount}'
      ' | session_started: ${selectedFlow.sessionStartCount}'
      ' | session_done: ${selectedFlow.sessionDoneCount}',
    );

  if (selectedFlow.remountEvidence.isNotEmpty) {
    buffer.writeln('Remount evidence:');
    for (final code in selectedFlow.remountEvidence) {
      buffer.writeln('- $code');
    }
  } else {
    buffer.writeln('Remount evidence: none');
  }

  if (selectedFlow.anomalyCodes.isNotEmpty) {
    buffer.writeln('Flow anomalies: ${selectedFlow.anomalyCodes.join(', ')}');
  } else {
    buffer.writeln('Flow anomalies: none');
  }
  buffer.writeln(
    'Flow summary: ${selectedFlow.summaryLabel}'
    ' | signals=${selectedFlow.summarySignals.isEmpty ? '[]' : selectedFlow.summarySignals.join(', ')}',
  );

  final primary = selectedFlow.primaryAttempt;
  if (primary != null) {
    buffer
      ..writeln(
          'Primary attempt: #${primary.attemptIndex} ${primary.sessionId}')
      ..writeln(
        '  phase: ${primary.phaseSummary ?? primary.phase ?? '-'}'
        ' | verdict: ${primary.verdict ?? '-'}'
        ' | heightPattern: ${primary.heightPattern ?? '-'}',
      )
      ..writeln(
        '  durationMs: ${primary.totalStreamingDurationMs ?? '-'}'
        ' | firstSuccessfulRenderAtMs: ${primary.firstSuccessfulRenderAtMs ?? '-'}'
        ' | tailWindowMs: ${primary.tailWindowMs ?? '-'}',
      )
      ..writeln(
        '  source/apply/dom/heightApplied: '
        '${primary.sourceProgressCount}/${primary.applyCount}/${primary.domCommitCount}/${primary.heightAppliedCount}',
      )
      ..writeln(
        '  max/final/drop: ${_fmtDouble(primary.maxAppliedHeight)}'
        '/${_fmtDouble(primary.finalAppliedHeight)}'
        '/${_fmtDouble(primary.largestDropPx)}',
      );
    if (primary.derivedSignals.isNotEmpty) {
      buffer.writeln('  signals: ${primary.derivedSignals.join(', ')}');
    }
    if (primary.anomalyCodes.isNotEmpty) {
      buffer.writeln('  anomalies: ${primary.anomalyCodes.join(', ')}');
    }
  }

  if (selectedFlow.attempts.length > 1) {
    buffer.writeln('Other attempts:');
    for (final attempt in selectedFlow.attempts) {
      final prefix =
          primary != null && attempt.attemptIndex == primary.attemptIndex
              ? '*'
              : '-';
      buffer.writeln(
        '$prefix #${attempt.attemptIndex} ${attempt.sessionId}'
        ' phase=${attempt.phaseSummary ?? attempt.phase ?? '-'}'
        ' durationMs=${attempt.totalStreamingDurationMs ?? '-'}'
        ' heightApplied=${attempt.heightAppliedCount}'
        ' signals=${attempt.derivedSignals.isEmpty ? '[]' : attempt.derivedSignals.join(',')}'
        ' anomalies=${attempt.anomalyCodes.isEmpty ? '[]' : attempt.anomalyCodes.join(',')}'
        '${attempt.supersededByRemount ? ' superseded=true' : ''}',
      );
    }
  }

  if (analysis.flows.length > 1) {
    buffer.writeln('Other flows:');
    for (final flow in analysis.flows.skip(1)) {
      buffer.writeln(
        '- ${flow.flowId} attempts=${flow.renderAttemptCount} anomalies=${flow.anomalyCodes.length}',
      );
    }
  }

  return buffer.toString().trimRight();
}

String _formatIncidentReport(
  ArtifactRenderLogAnalysis analysis, {
  String? requestedFlowId,
}) {
  final selectedFlow = analysis.selectedFlow;
  if (selectedFlow == null) {
    if (requestedFlowId != null) {
      return 'Incident report unavailable: missing flow ($requestedFlowId)';
    }
    return 'Incident report unavailable: no flow selected';
  }

  final report = selectedFlow.incidentReport;
  final buffer = StringBuffer()
    ..writeln('Artifact incident report')
    ..writeln('Flow: ${selectedFlow.flowId}')
    ..writeln('Headline: ${report.headline}')
    ..writeln(
      'Summary signals: ${selectedFlow.summarySignals.isEmpty ? '[]' : selectedFlow.summarySignals.join(', ')}',
    );

  if (report.findings.isNotEmpty) {
    buffer.writeln('Findings:');
    for (final finding in report.findings) {
      buffer.writeln('- $finding');
    }
  } else {
    buffer.writeln('Findings: none');
  }

  final primary = selectedFlow.primaryAttempt;
  if (primary != null) {
    buffer
      ..writeln('Primary attempt:')
      ..writeln(
        '- #${primary.attemptIndex} ${primary.sessionId}',
      )
      ..writeln(
        '- phase=${primary.phaseSummary ?? primary.phase ?? '-'}'
        ' heightPattern=${primary.heightPattern ?? '-'}'
        ' durationMs=${primary.totalStreamingDurationMs ?? '-'}',
      )
      ..writeln(
        '- max/final/drop=${_fmtDouble(primary.maxAppliedHeight)}/'
        '${_fmtDouble(primary.finalAppliedHeight)}/'
        '${_fmtDouble(primary.largestDropPx)}',
      )
      ..writeln(
        '- signals=${primary.derivedSignals.isEmpty ? '[]' : primary.derivedSignals.join(', ')}'
        ' anomalies=${primary.anomalyCodes.isEmpty ? '[]' : primary.anomalyCodes.join(', ')}',
      );
  }

  return buffer.toString().trimRight();
}

String _fmtDouble(double? value) {
  if (value == null) {
    return '-';
  }
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

class _CliArguments {
  const _CliArguments({
    required this.logPath,
    required this.flowId,
    required this.asJson,
    required this.asReport,
    required this.showHelp,
  });

  final String? logPath;
  final String? flowId;
  final bool asJson;
  final bool asReport;
  final bool showHelp;

  static _CliArguments parse(List<String> args) {
    String? logPath;
    String? flowId;
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
        case '--flow-id':
          if (i + 1 >= args.length) {
            showHelp = true;
            break;
          }
          flowId = args[i + 1];
          i += 1;
          break;
        default:
          logPath ??= arg;
          break;
      }
    }

    return _CliArguments(
      logPath: logPath,
      flowId: flowId,
      asJson: asJson,
      asReport: asReport,
      showHelp: showHelp,
    );
  }
}

const String _usage = '''
Usage:
  dart run tool/analyze_create_artifact_render_log.dart <log_path> [--flow-id <flowId>] [--json] [--report]

Examples:
  dart run tool/analyze_create_artifact_render_log.dart build/artifact-debug/create_artifact_latest.log
  dart run tool/analyze_create_artifact_render_log.dart build/artifact-debug/create_artifact_latest.log --flow-id turn_1:artifact_1:call_1
  dart run tool/analyze_create_artifact_render_log.dart build/artifact-debug/create_artifact_latest.log --json
  dart run tool/analyze_create_artifact_render_log.dart build/artifact-debug/create_artifact_latest.log --report
''';
