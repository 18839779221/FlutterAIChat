import 'package:ai_chat/models/chat/tool_card_presentation_model.dart';
import 'package:ai_chat/models/chat/tool_card_presentation_variant.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_exception_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('exception card shows reason and next-step guidance text',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ToolExceptionCard(
            model: ToolCardPresentationModel(
              variant: ToolCardPresentationVariant.exceptionCard,
              title: '联网搜索失败',
              summary: '缺少 API Key',
              primaryFields: {
                'reason': 'missing_api_key',
                'nextStep': '请先在设置中配置 API Key',
              },
              statusLabel: '失败',
            ),
          ),
        ),
      ),
    );

    expect(find.text('联网搜索失败'), findsOneWidget);
    expect(find.text('缺少 API Key'), findsOneWidget);
    expect(find.text('请先在设置中配置 API Key'), findsOneWidget);
  });
}
