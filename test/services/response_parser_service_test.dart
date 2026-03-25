import 'package:ai_chat/services/response_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResponseParserService.parseStructuredSummaryCard', () {
    test('合法 json 时返回结构化卡片', () {
      final service = ResponseParserService();

      final result = service.parseStructuredSummaryCard(
        '{"title":"Weekly Summary","summary":"A short summary","keyPoints":["A"],"actionItems":["B"],"risks":["C"]}',
      );

      expect(result.isStructuredCard, isTrue);
      expect(result.card?.title, 'Weekly Summary');
      expect(result.card?.summary, 'A short summary');
      expect(result.card?.keyPoints, ['A']);
      expect(result.card?.actionItems, ['B']);
      expect(result.card?.risks, ['C']);
      expect(result.fallbackText, isNull);
    });

    test('非法 json 时返回普通文本回退结果', () {
      final service = ResponseParserService();

      final result = service.parseStructuredSummaryCard('not-json');

      expect(result.isStructuredCard, isFalse);
      expect(result.card, isNull);
      expect(result.fallbackText, '结构化整理失败，请重试。');
    });

    test('缺失必填字段时返回普通文本回退结果', () {
      final service = ResponseParserService();

      final result = service.parseStructuredSummaryCard(
        '{"title":"Weekly Summary","summary":"A short summary","keyPoints":["A"],"actionItems":["B"]}',
      );

      expect(result.isStructuredCard, isFalse);
      expect(result.card, isNull);
      expect(result.fallbackText, '结构化整理失败，请重试。');
    });

    test('字段类型错误时返回普通文本回退结果', () {
      final service = ResponseParserService();

      final result = service.parseStructuredSummaryCard(
        '{"title":"Weekly Summary","summary":"A short summary","keyPoints":"A","actionItems":["B"],"risks":["C"]}',
      );

      expect(result.isStructuredCard, isFalse);
      expect(result.card, isNull);
      expect(result.fallbackText, '结构化整理失败，请重试。');
    });
  });
}
