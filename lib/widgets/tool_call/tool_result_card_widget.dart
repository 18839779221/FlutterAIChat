import 'package:flutter/material.dart';

import '../../models/tool/tool_result.dart';

/// Renders the final outcome of a tool execution.
class ToolResultCardWidget extends StatelessWidget {
  /// Final tool result payload shown to the user.
  final ToolResult result;

  const ToolResultCardWidget({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess = result.status == ToolExecutionStatus.success;
    final backgroundColor = isSuccess ? Colors.green.shade50 : Colors.red.shade50;
    final borderColor = isSuccess ? Colors.green.shade200 : Colors.red.shade200;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSuccess ? '工具执行完成' : '工具执行失败',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(result.summary),
          if (result.errorMessage != null && result.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '错误：${result.errorMessage}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}
