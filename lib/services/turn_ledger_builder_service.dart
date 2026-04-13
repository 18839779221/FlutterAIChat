import 'dart:convert';

import '../models/agent/chat_turn_step.dart';
import '../models/chat_turn.dart';

class TurnLedgerBuilderService {
  const TurnLedgerBuilderService();

  String buildPlannerSummary({
    required ChatTurn turn,
    required List<ChatTurnStep> steps,
  }) {
    final lines = <String>[
      '用户目标：${turn.userInput}',
      if ((turn.goalSummary ?? '').trim().isNotEmpty)
        '目标摘要：${turn.goalSummary}',
    ];

    final completedSteps = steps
        .where((step) => step.status == ChatTurnStepStatus.completed)
        .toList(growable: false);
    if (completedSteps.isNotEmpty) {
      lines.add('已完成步骤：');
      lines.addAll(completedSteps.map(_formatCompletedStep));
    }

    final pendingSteps = steps
        .where((step) =>
            step.status == ChatTurnStepStatus.planned ||
            step.status == ChatTurnStepStatus.running)
        .toList(growable: false);
    if (pendingSteps.isNotEmpty) {
      lines.add('待完成步骤：');
      lines.addAll(pendingSteps.map(_formatPendingStep));
    }

    final failedSteps = steps
        .where((step) => step.status == ChatTurnStepStatus.failed)
        .toList(growable: false);
    if (failedSteps.isNotEmpty) {
      lines.add('失败步骤：');
      lines.addAll(failedSteps.map(_formatFailedStep));
    }

    return lines.join('\n');
  }

  String buildFinalAnswerSummary({
    required ChatTurn turn,
    required List<ChatTurnStep> steps,
  }) {
    final lines = <String>[
      '用户目标：${turn.userInput}',
      if ((turn.goalSummary ?? '').trim().isNotEmpty)
        '目标摘要：${turn.goalSummary}',
      '本轮工具执行总结：',
    ];

    final completedSteps = steps
        .where((step) => step.status == ChatTurnStepStatus.completed)
        .toList(growable: false);
    if (completedSteps.isEmpty) {
      lines.add('本轮未执行工具。');
      return lines.join('\n');
    }

    lines.addAll(completedSteps.map(_formatCompletedStep));
    final failedSteps = steps
        .where((step) => step.status == ChatTurnStepStatus.failed)
        .toList(growable: false);
    if (failedSteps.isNotEmpty) {
      lines.add('失败步骤：');
      lines.addAll(failedSteps.map(_formatFailedStep));
    }
    return lines.join('\n');
  }

  String _formatCompletedStep(ChatTurnStep step) {
    final buffer = StringBuffer()
      ..write('${step.stepIndex}. ${step.toolName}')
      ..write(' args=${_compactJson(step.toolArgsJson)}');
    if ((step.resultSummary ?? '').trim().isNotEmpty) {
      buffer.write(' result=${step.resultSummary}');
    }
    if ((step.resultJson ?? const {}).isNotEmpty) {
      buffer.write(' data=${_compactJson(step.resultJson!)}');
    }
    return buffer.toString();
  }

  String _formatPendingStep(ChatTurnStep step) {
    return '${step.stepIndex}. ${step.toolName} args=${_compactJson(step.toolArgsJson)}';
  }

  String _formatFailedStep(ChatTurnStep step) {
    final buffer = StringBuffer()..write('${step.stepIndex}. ${step.toolName}');
    if ((step.errorCode ?? '').trim().isNotEmpty) {
      buffer.write(' error=${step.errorCode}');
    }
    if ((step.resultSummary ?? '').trim().isNotEmpty) {
      buffer.write(' summary=${step.resultSummary}');
    }
    if ((step.resultJson ?? const {}).isNotEmpty) {
      buffer.write(' data=${_compactJson(step.resultJson!)}');
    }
    return buffer.toString();
  }

  String _compactJson(Map<String, dynamic> value) {
    return jsonEncode(_compactValue(value, depth: 0));
  }

  Object? _compactValue(Object? value, {required int depth}) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length <= 120) {
        return normalized;
      }
      return '${normalized.substring(0, 117)}...';
    }
    if (value is num || value is bool) {
      return value;
    }
    if (value is List) {
      if (depth >= 2) {
        return '[${value.length} items]';
      }
      final items = value
          .take(3)
          .map((item) => _compactValue(item, depth: depth + 1))
          .toList(growable: true);
      if (value.length > 3) {
        items.add('...(${value.length - 3} more)');
      }
      return items;
    }
    if (value is Map) {
      if (depth >= 2) {
        return '{${value.length} keys}';
      }
      final entries = value.entries.take(5);
      final compact = <String, Object?>{};
      for (final entry in entries) {
        compact[entry.key.toString()] =
            _compactValue(entry.value, depth: depth + 1);
      }
      if (value.length > 5) {
        compact['__truncated__'] = '${value.length - 5} more';
      }
      return compact;
    }
    return value.toString();
  }
}
