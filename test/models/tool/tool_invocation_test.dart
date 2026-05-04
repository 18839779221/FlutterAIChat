import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolInvocation', () {
    test('can parse a valid invocation payload', () {
      final invocation = ToolInvocation.fromJson(const {
        'toolName': 'create_reminder',
        'arguments': {
          'title': '交周报',
        },
        'status': 'awaitingConfirmation',
        'summary': '准备创建提醒：交周报',
        'requiresConfirmation': true,
      });

      expect(invocation.toolName, 'create_reminder');
      expect(invocation.arguments, containsPair('title', '交周报'));
      expect(invocation.status, ToolInvocationStatus.awaitingConfirmation);
      expect(invocation.summary, '准备创建提醒：交周报');
      expect(invocation.requiresConfirmation, isTrue);
    });

    test('rejects empty tool name', () {
      expect(
        () => ToolInvocation.fromJson(const {
          'toolName': '',
          'arguments': {},
          'status': 'proposed',
        }),
        throwsFormatException,
      );
    });
  });

  group('ToolResult', () {
    test('round-trips richer result payload fields', () {
      const result = ToolResult(
        toolName: 'fetch_webpage',
        status: ToolExecutionStatus.success,
        summary: '已读取网页',
        data: {
          'url': 'https://example.com',
          'message': '网页处理结果：example.com 首页概览',
        },
        executionPolicy: 'auto_run',
        toolAccess: {
          'toolName': 'fetch_webpage',
          'executionDecision': 'autoRun',
          'executionPolicy': 'auto_run',
          'isVisibleToPlanner': true,
        },
        errorMessage: null,
      );

      final decoded = ToolResult.fromJson(result.toJson());

      expect(decoded.toolName, 'fetch_webpage');
      expect(decoded.status, ToolExecutionStatus.success);
      expect(decoded.summary, '已读取网页');
      expect(decoded.data, containsPair('url', 'https://example.com'));
      expect(decoded.data, containsPair('message', '网页处理结果：example.com 首页概览'));
      expect(decoded.executionPolicy, 'auto_run');
      expect(decoded.toolAccess, containsPair('executionPolicy', 'auto_run'));
      expect(decoded.errorMessage, isNull);
    });

    test('serializes policy from toolAccess without duplicating top-level field', () {
      const result = ToolResult(
        toolName: 'fetch_webpage',
        status: ToolExecutionStatus.success,
        summary: '已读取网页',
        toolAccess: {
          'toolName': 'fetch_webpage',
          'executionDecision': 'autoRun',
          'executionPolicy': 'auto_run',
          'isVisibleToPlanner': true,
        },
      );

      final json = result.toJson();

      expect(json['executionPolicy'], isNull);
      expect(
        (json['toolAccess'] as Map<String, dynamic>)['executionPolicy'],
        'auto_run',
      );
    });

    test('serializes summary and data without legacy fields', () {
      const result = ToolResult(
        toolName: 'web_search',
        status: ToolExecutionStatus.success,
        summary: '已执行联网搜索',
        data: {
          'query': 'OpenAI latest docs',
          'results': [
            {
              'title': 'OpenAI 发布新文档',
              'url': 'https://platform.openai.com',
            },
          ],
        },
      );

      final json = result.toJson();

      expect(json['summary'], '已执行联网搜索');
      expect((json['data'] as Map<String, dynamic>)['query'], 'OpenAI latest docs');
      expect(json.containsKey('toolResultText'), isFalse);
      expect(json.containsKey('contextText'), isFalse);
      expect(json.containsKey('uiSummaryText'), isFalse);
    });

    test('does not expose planner-facing text helper on ToolResult', () {
      const result = ToolResult(
        toolName: 'Read',
        status: ToolExecutionStatus.success,
        summary: '已读取文件：demo.md',
        data: {
          'filePath': 'demo.md',
          'message': '裁剪后的文件内容',
        },
      );

      expect(result.summary, '已读取文件：demo.md');
      expect(result.data, containsPair('message', '裁剪后的文件内容'));
    });
  });

  group('MessageContentType', () {
    test('parses the new tool-related content types', () {
      expect(
        MessageContentTypeParsing.fromString('toolInvocation'),
        MessageContentType.toolInvocation,
      );
      expect(
        MessageContentTypeParsing.fromString('actionConfirmation'),
        MessageContentType.actionConfirmation,
      );
      expect(
        MessageContentTypeParsing.fromString('askUserQuestionPrompt'),
        MessageContentType.askUserQuestionPrompt,
      );
      expect(
        MessageContentTypeParsing.fromString('askUserQuestionResult'),
        MessageContentType.askUserQuestionResult,
      );
    });
  });
}
