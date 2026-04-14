import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_access_snapshot.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/services/planner_tool_exposure_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlannerToolExposureService', () {
    test('返回全部可用工具，不按用户文案做额外裁剪', () {
      final service = PlannerToolExposureService();
      final visible = service.selectVisibleToolAccess(
        userInput: '请帮我读一下 https://example.com 这篇文章',
        allTools: _snapshotsFromDefinitions(_definitions),
      );

      expect(
          visible.map((tool) => tool.definition.name),
          containsAll([
            'fetch_webpage',
            'share_result',
            'create_reminder',
            'Write',
            'Edit',
          ]));
    });

    test('纯检索问题也不在这里隐藏写工具', () {
      final service = PlannerToolExposureService();
      final visible = service.selectVisibleToolAccess(
        userInput: '帮我查一下 OpenAI 最近的发布',
        allTools: _snapshotsFromDefinitions(_definitions),
      );

      expect(
          visible.map((tool) => tool.definition.name),
          containsAll([
            'web_search',
            'create_reminder',
            'share_result',
            'Write',
            'Edit',
          ]));
    });

    test('文件查看问题不在这里排除写工具', () {
      final service = PlannerToolExposureService();
      final visible = service.selectVisibleToolAccess(
        userInput: '帮我读取文件内容，先看看有哪些文件',
        allTools: _snapshotsFromDefinitions(_definitions),
      );

      expect(
          visible.map((tool) => tool.definition.name),
          containsAll([
            'Glob',
            'Grep',
            'Read',
            'Write',
            'Edit',
          ]));
    });

    test('保留去重行为', () {
      final service = PlannerToolExposureService();
      final visible = service.selectVisibleToolAccess(
        userInput: '随便什么问题',
        allTools: _snapshotsFromDefinitions(const [
          ToolDefinition(
            name: 'Read',
            title: '读取文件',
            description: '读取文件内容',
            category: ToolCategory.retrieval,
          ),
          ToolDefinition(
            name: 'Read',
            title: '读取文件-重复',
            description: '重复定义',
            category: ToolCategory.retrieval,
          ),
          ToolDefinition(
            name: 'Write',
            title: '写入文件',
            description: '写入文件内容',
            category: ToolCategory.productivity,
          ),
        ]),
      );

      expect(
        visible.map((tool) => tool.definition.name).toList(),
        ['Read', 'Write'],
      );
    });

    test('隐藏被 policy block 的工具', () {
      final service = PlannerToolExposureService();
      final visible = service.selectVisibleToolAccess(
        userInput: '提醒我明天开会',
        allTools: _snapshotsFromDefinitions(
          _definitions,
          blockedToolNames: const {'create_reminder', 'share_result'},
        ),
      );

      expect(
        visible.map((tool) => tool.definition.name),
        isNot(contains('create_reminder')),
      );
      expect(
        visible.map((tool) => tool.definition.name),
        isNot(contains('share_result')),
      );
      expect(visible.map((tool) => tool.definition.name), contains('web_search'));
    });

    test('selectVisibleToolAccess 保留 access snapshot 语义', () {
      final service = PlannerToolExposureService();
      final visible = service.selectVisibleToolAccess(
        userInput: '提醒我明天开会',
        allTools: const [
          ToolAccessSnapshot(
            definition: ToolDefinition(
              name: 'web_search',
              title: '联网搜索',
              description: '搜索外部网页',
            ),
            executionDecision: ToolPolicyDecision.autoRun,
            executionPolicyLabel: 'auto_run',
            isVisibleToPlanner: true,
          ),
          ToolAccessSnapshot(
            definition: ToolDefinition(
              name: 'create_reminder',
              title: '创建提醒',
              description: '创建系统提醒',
            ),
            executionDecision: ToolPolicyDecision.requireConfirmation,
            executionPolicyLabel: 'require_confirmation',
            isVisibleToPlanner: true,
          ),
          ToolAccessSnapshot(
            definition: ToolDefinition(
              name: 'create_reminder',
              title: '创建提醒-重复',
              description: '重复定义',
            ),
            executionDecision: ToolPolicyDecision.requireConfirmation,
            executionPolicyLabel: 'require_confirmation',
            isVisibleToPlanner: true,
          ),
          ToolAccessSnapshot(
            definition: ToolDefinition(
              name: 'share_result',
              title: '分享结果',
              description: '分享文本',
            ),
            executionDecision: ToolPolicyDecision.blocked,
            executionPolicyLabel: 'blocked',
            isVisibleToPlanner: false,
          ),
        ],
      );

      expect(visible.map((tool) => tool.definition.name).toList(), [
        'web_search',
        'create_reminder',
      ]);
      expect(
        visible.last.executionPolicyLabel,
        'require_confirmation',
      );
    });

    test('planner exposure 只消费 ToolAccessSnapshot，不再额外依赖 blocked name set', () {
      final service = PlannerToolExposureService();
      final visible = service.selectVisibleToolAccess(
        userInput: '提醒我明天开会',
        allTools: const [
          ToolAccessSnapshot(
            definition: ToolDefinition(
              name: 'create_reminder',
              title: '创建提醒',
              description: '创建系统提醒',
            ),
            executionDecision: ToolPolicyDecision.blocked,
            executionPolicyLabel: 'blocked',
            isVisibleToPlanner: true,
          ),
          ToolAccessSnapshot(
            definition: ToolDefinition(
              name: 'web_search',
              title: '联网搜索',
              description: '搜索外部网页',
            ),
            executionDecision: ToolPolicyDecision.autoRun,
            executionPolicyLabel: 'auto_run',
            isVisibleToPlanner: true,
          ),
        ],
      );

      expect(
        visible.map((tool) => tool.definition.name).toList(),
        ['create_reminder', 'web_search'],
      );
      expect(
        visible.first.executionDecision,
        ToolPolicyDecision.blocked,
      );
    });

    test('snapshot 输入可显式承接 blocked 策略', () {
      final service = PlannerToolExposureService();
      final visible = service.selectVisibleToolAccess(
        userInput: '提醒我明天开会',
        allTools: _snapshotsFromDefinitions(
          _definitions,
          blockedToolNames: const {'create_reminder'},
        ),
      );

      expect(
        visible.map((tool) => tool.definition.name),
        isNot(contains('create_reminder')),
      );
      expect(visible.map((tool) => tool.definition.name), contains('web_search'));
    });
  });
}

List<ToolAccessSnapshot> _snapshotsFromDefinitions(
  List<ToolDefinition> definitions, {
  Set<String> blockedToolNames = const {},
}) {
  return definitions
      .map(
        (tool) => ToolAccessSnapshot.fromLegacyDefinition(
          definition: tool,
          isBlocked: blockedToolNames.contains(tool.name),
        ),
      )
      .toList(growable: false);
}

const _definitions = [
  ToolDefinition(
    name: 'web_search',
    title: '联网搜索',
    description: '搜索外部网页',
    descriptionForModel: '需要实时信息时使用。',
    category: ToolCategory.retrieval,
    capabilities: [ToolCapability.webSearch],
    argumentSchema: ToolArgumentSchema(
      properties: {
        'query': ToolArgumentProperty.string(description: '搜索词'),
      },
      required: ['query'],
    ),
  ),
  ToolDefinition(
    name: 'fetch_webpage',
    title: '读取网页',
    description: '读取网页内容',
    descriptionForModel: '用户已提供 URL 时使用。',
    category: ToolCategory.retrieval,
    capabilities: [ToolCapability.webUrlReader],
    argumentSchema: ToolArgumentSchema(
      properties: {
        'url': ToolArgumentProperty.string(description: '网页链接', format: 'uri'),
      },
      required: ['url'],
    ),
  ),
  ToolDefinition(
    name: 'Glob',
    title: '查找文件',
    description: '按路径模式查找文件',
    descriptionForModel: '需要按文件名或路径模式找文件时使用。',
    category: ToolCategory.retrieval,
    capabilities: [ToolCapability.fileDiscovery],
    argumentSchema: ToolArgumentSchema(
      properties: {
        'pattern': ToolArgumentProperty.string(description: 'glob pattern'),
      },
      required: ['pattern'],
    ),
  ),
  ToolDefinition(
    name: 'Grep',
    title: '搜索文件内容',
    description: '按内容模式搜索文件',
    descriptionForModel: '需要按关键字或正则搜索文件内容时使用。',
    category: ToolCategory.retrieval,
    capabilities: [ToolCapability.fileDiscovery],
    argumentSchema: ToolArgumentSchema(
      properties: {
        'pattern': ToolArgumentProperty.string(description: 'regex pattern'),
      },
      required: ['pattern'],
    ),
  ),
  ToolDefinition(
    name: 'Read',
    title: '读取文件',
    description: '读取文件内容',
    descriptionForModel: '当已知文件路径并需要查看内容时使用。',
    category: ToolCategory.retrieval,
    capabilities: [ToolCapability.fileRead],
    argumentSchema: ToolArgumentSchema(
      properties: {
        'file_path': ToolArgumentProperty.string(description: '文件路径'),
      },
      required: ['file_path'],
    ),
  ),
  ToolDefinition(
    name: 'Write',
    title: '写入文件',
    description: '创建或覆盖文件',
    descriptionForModel: '当用户明确要求新建文件或整文件覆盖时使用。',
    category: ToolCategory.productivity,
    capabilities: [ToolCapability.fileWrite],
    argumentSchema: ToolArgumentSchema(
      properties: {
        'file_path': ToolArgumentProperty.string(description: '文件路径'),
        'content': ToolArgumentProperty.string(description: '完整内容'),
      },
      required: ['file_path', 'content'],
    ),
    requiresConfirmation: true,
    riskLevel: 'high',
  ),
  ToolDefinition(
    name: 'Edit',
    title: '编辑文件',
    description: '精确替换文件片段',
    descriptionForModel: '当用户要求修改已有文件时使用。',
    category: ToolCategory.productivity,
    capabilities: [ToolCapability.fileEdit],
    argumentSchema: ToolArgumentSchema(
      properties: {
        'file_path': ToolArgumentProperty.string(description: '文件路径'),
        'old_string': ToolArgumentProperty.string(description: '原始片段'),
        'new_string': ToolArgumentProperty.string(description: '新片段'),
      },
      required: ['file_path', 'old_string', 'new_string'],
    ),
    requiresConfirmation: true,
    riskLevel: 'medium',
  ),
  ToolDefinition(
    name: 'create_reminder',
    title: '创建提醒',
    description: '创建系统提醒',
    descriptionForModel: '用户明确要求提醒时使用。',
    category: ToolCategory.productivity,
    capabilities: [ToolCapability.reminderCreate],
    argumentSchema: ToolArgumentSchema(
      properties: {
        'title': ToolArgumentProperty.string(description: '标题'),
        'dueAt': ToolArgumentProperty.string(description: '时间'),
      },
      required: ['title', 'dueAt'],
    ),
    requiresConfirmation: true,
    riskLevel: 'medium',
  ),
  ToolDefinition(
    name: 'share_result',
    title: '分享结果',
    description: '分享文本',
    descriptionForModel: '用户明确要求分享时使用。',
    category: ToolCategory.outputAction,
    capabilities: [ToolCapability.shareResult],
    argumentSchema: ToolArgumentSchema(
      properties: {
        'text': ToolArgumentProperty.string(description: '正文'),
      },
      required: ['text'],
    ),
    requiresConfirmation: true,
    riskLevel: 'high',
  ),
];
