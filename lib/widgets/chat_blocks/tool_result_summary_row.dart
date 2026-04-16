import 'package:ai_chat/models/chat/tool_card_presentation_variant.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/tool_card_presentation_mapper.dart';
import 'package:flutter/material.dart';

import 'tool_exception_card.dart';
import 'tool_inline_step_row.dart';
import 'tool_outcome_card.dart';

/// Collapsed one-row-ish summary surface for completed tool work.
class ToolResultSummaryRow extends StatelessWidget {
  final ToolResult result;

  const ToolResultSummaryRow({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final model = ToolCardPresentationMapper.mapResult(result);
    return switch (model.variant) {
      ToolCardPresentationVariant.outcomeCard => ToolOutcomeCard(model: model),
      ToolCardPresentationVariant.exceptionCard =>
        ToolExceptionCard(model: model),
      _ => ToolInlineStepRow(model: model),
    };
  }
}
