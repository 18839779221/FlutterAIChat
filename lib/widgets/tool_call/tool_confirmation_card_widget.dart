import 'package:flutter/material.dart';

import '../../models/tool/tool_invocation.dart';

/// Renders a confirmation card for a pending tool action.
class ToolConfirmationCardWidget extends StatelessWidget {
  /// Invocation payload that describes the pending tool and user-facing summary.
  final ToolInvocation invocation;

  /// Triggered when the user approves this single execution.
  final VoidCallback? onContinue;

  /// Triggered when the user rejects this execution.
  final VoidCallback? onCancel;

  /// Triggered when the user approves and trusts the tool for future calls.
  final VoidCallback? onContinueAndTrust;

  const ToolConfirmationCardWidget({
    super.key,
    required this.invocation,
    this.onContinue,
    this.onCancel,
    this.onContinueAndTrust,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '待确认操作',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(invocation.summary),
          const SizedBox(height: 6),
          Text(
            '工具：${invocation.toolName}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: onContinue,
                child: const Text('继续'),
              ),
              OutlinedButton(
                onPressed: onCancel,
                child: const Text('取消'),
              ),
              OutlinedButton(
                onPressed: onContinueAndTrust,
                child: const Text('继续，以后不再确认'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
