import 'package:flutter/material.dart';

import '../../models/chat/tool_card_presentation_model.dart';
import '../../models/chat/tool_card_presentation_variant.dart';
import '../../models/tool/tool_result.dart';
import '../chat_blocks/tool_inline_step_row.dart';
import 'file_change_preview.dart';
import 'file_tool_result_surface.dart';

class EditToolResultCard extends StatelessWidget {
  const EditToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  Widget build(BuildContext context) {
    final data = result.data;
    final filePath = (data['filePath'] ?? '').toString();
    final oldContentPreview = (data['oldContentPreview'] ?? '').toString();
    final newContentPreview = (data['newContentPreview'] ?? '').toString();
    final hasPreview =
        oldContentPreview.isNotEmpty || newContentPreview.isNotEmpty;

    if (!hasPreview) {
      return ToolInlineStepRow(
        model: ToolCardPresentationModel(
          variant: ToolCardPresentationVariant.inlineStep,
          title: result.status == ToolExecutionStatus.failure ? '编辑失败' : '编辑文件',
          summary: result.summary,
          statusLabel: result.statusLabel,
        ),
      );
    }

    return FileToolResultSurface(
      filePath: filePath,
      statusText: '已修改',
      child: FileChangePreview(
        filePath: filePath,
        oldContent: oldContentPreview,
        newContent: newContentPreview,
        truncated: data['contentPreviewTruncated'] == true,
      ),
    );
  }
}
