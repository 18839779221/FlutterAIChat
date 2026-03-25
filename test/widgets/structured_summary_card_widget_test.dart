import 'package:ai_chat/models/response/structured_summary_card.dart';
import 'package:ai_chat/widgets/structured_message/structured_summary_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StructuredSummaryCardWidget', () {
    testWidgets('renders title summary and list sections', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StructuredSummaryCardWidget(
              card: const StructuredSummaryCard(
                title: 'Weekly Summary',
                summary: 'A short summary',
                keyPoints: ['Point A'],
                actionItems: ['Action B'],
                risks: ['Risk C'],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Weekly Summary'), findsOneWidget);
      expect(find.text('A short summary'), findsOneWidget);
      expect(find.text('关键点'), findsOneWidget);
      expect(find.text('行动项'), findsOneWidget);
      expect(find.text('风险'), findsOneWidget);
      expect(find.text('Point A'), findsOneWidget);
      expect(find.text('Action B'), findsOneWidget);
      expect(find.text('Risk C'), findsOneWidget);
    });

    testWidgets('empty lists do not crash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StructuredSummaryCardWidget(
              card: const StructuredSummaryCard(
                title: 'Weekly Summary',
                summary: 'A short summary',
                keyPoints: [],
                actionItems: [],
                risks: [],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Weekly Summary'), findsOneWidget);
      expect(find.text('A short summary'), findsOneWidget);
    });
  });
}
