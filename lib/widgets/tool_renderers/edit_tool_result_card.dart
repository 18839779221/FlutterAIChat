import 'package:flutter/material.dart';

import '../../models/tool/tool_result.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class EditToolResultCard extends StatefulWidget {
  const EditToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  State<EditToolResultCard> createState() => _EditToolResultCardState();
}

class _EditToolResultCardState extends State<EditToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final data = widget.result.data;
    final filePath = (data['filePath'] ?? '').toString();
    final replacementCount = data['replacementCount'];
    final oldLength = data['oldLength'];
    final newLength = data['newLength'];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.toolOutcomeSurface,
        borderRadius: BorderRadius.circular(radius.md + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            filePath,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (replacementCount is num) ...[
            SizedBox(height: spacing.xs),
            Text(
              '替换 ${replacementCount.toInt()} 处',
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (oldLength is num && newLength is num) ...[
            SizedBox(height: spacing.xxs),
            Text(
              '${oldLength.toInt()} -> ${newLength.toInt()} 字符',
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 12,
              ),
            ),
          ],
          SizedBox(height: spacing.xs),
          Text(
            widget.result.summary,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 12.5,
              height: 1.42,
            ),
          ),
          SizedBox(height: spacing.sm),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? '收起详情' : '查看详情'),
          ),
          if (_expanded) ...[
            if ((data['oldString'] ?? '').toString().isNotEmpty)
              _DetailLine(label: '', value: '${data['oldString']}'),
            if ((data['newString'] ?? '').toString().isNotEmpty)
              _DetailLine(label: '', value: '${data['newString']}'),
          ],
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.only(top: spacing.xxs),
      child: Text(
        label.isEmpty ? value : '$label: $value',
        style: TextStyle(
          color: colors.primaryText,
          fontSize: 11.5,
          height: 1.4,
        ),
      ),
    );
  }
}
