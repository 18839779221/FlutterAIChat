import 'package:ai_chat/models/chat/tool_card_presentation_model.dart';
import 'package:ai_chat/models/chat/tool_card_presentation_variant.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inline step row stays compact and shows single summary line',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ToolInlineStepRow(
            model: ToolCardPresentationModel(
              variant: ToolCardPresentationVariant.inlineStep,
              title: '联网搜索',
              summary: '已执行联网搜索',
              statusLabel: '完成',
            ),
          ),
        ),
      ),
    );

    expect(find.text('联网搜索'), findsOneWidget);
    expect(find.text('已执行联网搜索'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });
}
