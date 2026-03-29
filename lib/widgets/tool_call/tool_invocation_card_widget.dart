import 'package:flutter/material.dart';

import '../../models/tool/tool_invocation.dart';

/// Renders a compact invocation/running-state tool card.
class ToolInvocationCardWidget extends StatelessWidget {
  /// Invocation payload that drives the displayed status and summary.
  final ToolInvocation invocation;

  const ToolInvocationCardWidget({
    super.key,
    required this.invocation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '工具执行中',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(invocation.summary),
          const SizedBox(height: 6),
          Text(
            '状态：${invocation.status.name}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
