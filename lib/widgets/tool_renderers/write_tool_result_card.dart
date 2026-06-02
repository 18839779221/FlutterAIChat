import 'package:flutter/material.dart';

import '../../models/chat/tool_card_presentation_model.dart';
import '../../models/chat/tool_card_presentation_variant.dart';
import '../../models/tool/tool_result.dart';
import '../chat_blocks/tool_inline_step_row.dart';
import 'file_change_preview.dart';
import 'file_tool_result_surface.dart';

class WriteToolResultCard extends StatelessWidget {
  const WriteToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  Widget build(BuildContext context) {
    final data = result.data;
    final filePath = (data['filePath'] ?? '').toString();
    final existed = data['filePreviouslyExisted'] == true;
    final oldContentPreview = (data['oldContentPreview'] ?? '').toString();
    final newContentPreview = (data['newContentPreview'] ?? '').toString();
    final hasPreview =
        oldContentPreview.isNotEmpty || newContentPreview.isNotEmpty;

    if (!hasPreview) {
      return ToolInlineStepRow(
        model: ToolCardPresentationModel(
          variant: ToolCardPresentationVariant.inlineStep,
          title: result.status == ToolExecutionStatus.failure ? '写入失败' : '写入文件',
          summary: result.summary,
          statusLabel: result.statusLabel,
        ),
      );
    }

    return FileToolResultSurface(
      filePath: filePath,
      statusText: existed ? '已写入' : '已新建',
      child: FileChangePreview(
        filePath: filePath,
        oldContent: oldContentPreview,
        newContent: newContentPreview,
        truncated: data['contentPreviewTruncated'] == true,
        forceAdded: !existed,
      ),
    );
  }
}
