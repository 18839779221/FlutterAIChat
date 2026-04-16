import 'package:ai_chat/models/chat/tool_card_presentation_model.dart';
import 'package:ai_chat/models/chat/tool_card_presentation_variant.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_outcome_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('outcome card shows reminder title and due time', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ToolOutcomeCard(
            model: ToolCardPresentationModel(
              variant: ToolCardPresentationVariant.outcomeCard,
              title: '已发起提醒创建',
              summary: '设计评审',
              primaryFields: {
                'title': '设计评审',
                'dueAt': '明天 09:00',
              },
              statusLabel: '完成',
            ),
          ),
        ),
      ),
    );

    expect(find.text('已发起提醒创建'), findsOneWidget);
    expect(find.text('设计评审'), findsWidgets);
    expect(find.text('明天 09:00'), findsOneWidget);
  });
}
