/// Debug 用的测试案例定义。
///
/// 这些字段会被 App 内 UI 和未来自动化脚本共同消费，因此需要保持语义稳定。
class DebugTestCase {
  /// 稳定唯一标识，供自动化脚本和后续扩展引用。
  final String id;

  /// 主分组键，用于 Debug 面板的主题分段和未来自动化按组执行。
  final String group;

  /// 面板和空状态中展示的标题。
  final String title;

  /// 供列表快速扫读的一行简介。
  final String summary;

  /// 实际注入输入框或供自动化发送的完整消息。
  final String prompt;

  /// 用于轻量分组和未来自动化筛选的标签集合。
  final List<String> tags;

  /// 是否作为空状态精选案例展示。
  final bool featured;

  /// 是否启用该案例；禁用案例保留在文件中但不在 UI 中展示。
  final bool enabled;

  const DebugTestCase({
    required this.id,
    required this.group,
    required this.title,
    required this.summary,
    required this.prompt,
    required this.tags,
    required this.featured,
    required this.enabled,
  });

  factory DebugTestCase.fromJson(Map<String, dynamic> json) {
    String readRequiredString(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('DebugTestCase.$key 必须是字符串');
      }
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        throw FormatException('DebugTestCase.$key 不能为空');
      }
      return trimmed;
    }

    List<String> readTags() {
      final rawTags = json['tags'];
      if (rawTags is! List) {
        return const [];
      }
      return rawTags
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    return DebugTestCase(
      id: readRequiredString('id'),
      group: readRequiredString('group'),
      title: readRequiredString('title'),
      summary: readRequiredString('summary'),
      prompt: readRequiredString('prompt'),
      tags: readTags(),
      featured: json['featured'] == true,
      enabled: json['enabled'] != false,
    );
  }
}

/// Debug 案例库的根对象。
class DebugTestCaseLibrary {
  /// 文件 schema 版本，用于未来兼容演进。
  final int version;

  /// 已经过滤 `enabled == false` 后的可用案例列表。
  final List<DebugTestCase> allCases;

  const DebugTestCaseLibrary({
    required this.version,
    required this.allCases,
  });

  /// 空状态等轻入口使用的精选案例。
  List<DebugTestCase> get featuredCases =>
      allCases.where((item) => item.featured).toList(growable: false);
}
