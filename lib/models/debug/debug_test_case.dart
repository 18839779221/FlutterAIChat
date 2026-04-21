/// Debug / E2E 用的测试案例定义。
///
/// 这些字段会被 App 内 UI、调试面板和未来自动化脚本共同消费，因此需要保持语义稳定。
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

  /// 端到端执行前需要注入的环境。
  final DebugTestCaseSetup setup;

  /// 用于描述关键执行旅程的检查点。
  final List<String> checkpoints;

  /// 端到端执行完成后的验收条件。
  final DebugTestCaseAssertions assertions;

  const DebugTestCase({
    required this.id,
    required this.group,
    required this.title,
    required this.summary,
    required this.prompt,
    required this.tags,
    required this.featured,
    required this.enabled,
    required this.setup,
    required this.checkpoints,
    required this.assertions,
  });

  /// 是否为文件相关场景。
  bool get isFileCase => tags.contains('file');

  /// 是否为 AskUser 交互场景。
  bool get isAskUserCase => group == 'ask-user-question';

  /// 是否为启用中的精选案例。
  bool get isFeaturedEnabled => featured && enabled;

  /// 该案例是否期待出现最终回答。
  bool get expectsFinalAnswer => checkpoints.contains('finalAnswer');

  factory DebugTestCase.fromJson(Map<String, dynamic> json) {
    final id = _readRequiredString(json, 'id', scope: 'DebugTestCase');
    final scope = 'DebugTestCase.$id';
    final result = DebugTestCase(
      id: id,
      group: _readRequiredString(json, 'group', scope: scope),
      title: _readRequiredString(json, 'title', scope: scope),
      summary: _readRequiredString(json, 'summary', scope: scope),
      prompt: _readRequiredString(json, 'prompt', scope: scope),
      tags: _readStringList(
        json['tags'],
        fieldName: '$scope.tags',
        allowEmpty: true,
        allowMissing: true,
        dedupe: true,
      ),
      featured: json['featured'] == true,
      enabled: json['enabled'] != false,
      setup: DebugTestCaseSetup.fromJson(
        _readObject(json, 'setup', scope: scope),
        caseId: id,
      ),
      checkpoints: _readCheckpointList(
        json['checkpoints'],
        fieldName: '$scope.checkpoints',
      ),
      assertions: DebugTestCaseAssertions.fromJson(
        _readObject(json, 'assertions', scope: scope),
        caseId: id,
      ),
    );
    result._validateSemantics();
    return result;
  }

  void _validateSemantics() {
    if (featured && !enabled) {
      throw FormatException(
        'DebugTestCase.$id 不能同时 featured=true 且 enabled=false',
      );
    }

    final checkpointSet = checkpoints.toSet();
    for (var index = 0; index < setup.mutationsAfterCheckpoints.length; index++) {
      final mutation = setup.mutationsAfterCheckpoints[index];
      if (!checkpointSet.contains(mutation.after)) {
        throw FormatException(
          'DebugTestCase.$id.setup.mutationsAfterCheckpoints[$index].after 必须引用当前 case 的 checkpoint',
        );
      }
    }

    final seededPaths = setup.files.map((item) => item.path).toSet();
    for (var index = 0; index < setup.mutationsAfterCheckpoints.length; index++) {
      final mutation = setup.mutationsAfterCheckpoints[index];
      if (!seededPaths.contains(mutation.path)) {
        throw FormatException(
          'DebugTestCase.$id.setup.mutationsAfterCheckpoints[$index].path 必须先在 setup.files 中声明',
        );
      }
    }

    if (expectsFinalAnswer && !assertions.endStatus.contains('completed')) {
      throw FormatException(
        'DebugTestCase.$id 包含 finalAnswer checkpoint 时，assertions.endStatus 必须包含 completed',
      );
    }

    if (isAskUserCase && !checkpointSet.contains('askUser:prompted')) {
      throw FormatException(
        'DebugTestCase.$id 属于 ask-user-question 分组时，checkpoints 必须包含 askUser:prompted',
      );
    }

    if (assertions.finalFileContains.isNotEmpty && !_hasSuccessfulWriteCheckpoint()) {
      throw FormatException(
        'DebugTestCase.$id.assertions.finalFileContains 要求文件结果时，checkpoints 必须包含成功写操作',
      );
    }

    final changedPaths = assertions.finalFileContains.map((item) => item.path).toSet();
    final unchangedPaths = assertions.finalFileUnchanged.toSet();
    final conflicts = changedPaths.intersection(unchangedPaths);
    if (conflicts.isNotEmpty) {
      throw FormatException(
        'DebugTestCase.$id.assertions.finalFileContains 与 finalFileUnchanged 冲突: ${conflicts.join(', ')}',
      );
    }
  }

  bool _hasSuccessfulWriteCheckpoint() {
    return checkpoints.any(
      (item) => item == 'tool:Write:success' || item == 'tool:Edit:success',
    );
  }
}

/// 端到端执行前的输入环境。
class DebugTestCaseSetup {
  /// 预置的历史消息。
  final List<DebugTestCaseHistoryMessage> historyMessages;

  /// 预置的沙箱文件。
  final List<DebugTestCaseSeedFile> files;

  /// 在命中特定 checkpoint 后对文件施加的外部变更。
  final List<DebugTestCaseMutation> mutationsAfterCheckpoints;

  const DebugTestCaseSetup({
    required this.historyMessages,
    required this.files,
    required this.mutationsAfterCheckpoints,
  });

  factory DebugTestCaseSetup.fromJson(
    Map<String, dynamic> json, {
    required String caseId,
  }) {
    final scope = 'DebugTestCase.$caseId.setup';
    final historyMessages = _readObjectList(
      json['historyMessages'],
      fieldName: '$scope.historyMessages',
    ).asMap().entries.map((entry) {
      return DebugTestCaseHistoryMessage.fromJson(
        entry.value,
        scope: '$scope.historyMessages[${entry.key}]',
      );
    }).toList(growable: false);
    final files = _readObjectList(
      json['files'],
      fieldName: '$scope.files',
    ).asMap().entries.map((entry) {
      return DebugTestCaseSeedFile.fromJson(
        entry.value,
        scope: '$scope.files[${entry.key}]',
      );
    }).toList(growable: false);
    final mutations = _readObjectList(
      json['mutationsAfterCheckpoints'],
      fieldName: '$scope.mutationsAfterCheckpoints',
    ).asMap().entries.map((entry) {
      return DebugTestCaseMutation.fromJson(
        entry.value,
        scope: '$scope.mutationsAfterCheckpoints[${entry.key}]',
      );
    }).toList(growable: false);

    final pathCounts = <String, int>{};
    for (final file in files) {
      pathCounts[file.path] = (pathCounts[file.path] ?? 0) + 1;
    }
    final duplicatePaths = pathCounts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (duplicatePaths.isNotEmpty) {
      throw FormatException('$scope.files 存在重复 path: ${duplicatePaths.join(', ')}');
    }

    return DebugTestCaseSetup(
      historyMessages: historyMessages,
      files: files,
      mutationsAfterCheckpoints: mutations,
    );
  }
}

/// 预置的历史消息。
class DebugTestCaseHistoryMessage {
  /// 历史消息角色。
  final String role;

  /// 历史消息文本。
  final String text;

  const DebugTestCaseHistoryMessage({
    required this.role,
    required this.text,
  });

  factory DebugTestCaseHistoryMessage.fromJson(
    Map<String, dynamic> json, {
    required String scope,
  }) {
    final role = _readRequiredString(json, 'role', scope: scope);
    if (!kDebugCaseAllowedHistoryRoles.contains(role)) {
      throw FormatException('$scope.role 只允许 ${kDebugCaseAllowedHistoryRoles.join('/')}');
    }
    return DebugTestCaseHistoryMessage(
      role: role,
      text: _readRequiredString(json, 'text', scope: scope),
    );
  }
}

/// 预置的文件内容。
class DebugTestCaseSeedFile {
  /// 文件相对路径。
  final String path;

  /// 预置写入的文件内容。
  final String content;

  const DebugTestCaseSeedFile({
    required this.path,
    required this.content,
  });

  factory DebugTestCaseSeedFile.fromJson(
    Map<String, dynamic> json, {
    required String scope,
  }) {
    final path = _readRequiredString(json, 'path', scope: scope);
    _validateRelativePath(path, fieldName: '$scope.path');
    final content = json['content'];
    if (content is! String) {
      throw FormatException('$scope.content 必须是字符串');
    }
    return DebugTestCaseSeedFile(
      path: path,
      content: content,
    );
  }
}

/// 外部文件变更。
class DebugTestCaseMutation {
  /// 命中哪个 checkpoint 后执行该变更。
  final String after;

  /// 被变更的文件相对路径。
  final String path;

  /// 变更后的完整文件内容。
  final String content;

  const DebugTestCaseMutation({
    required this.after,
    required this.path,
    required this.content,
  });

  factory DebugTestCaseMutation.fromJson(
    Map<String, dynamic> json, {
    required String scope,
  }) {
    final path = _readRequiredString(json, 'path', scope: scope);
    _validateRelativePath(path, fieldName: '$scope.path');
    final content = json['content'];
    if (content is! String) {
      throw FormatException('$scope.content 必须是字符串');
    }
    return DebugTestCaseMutation(
      after: _readRequiredString(json, 'after', scope: scope),
      path: path,
      content: content,
    );
  }
}

/// 执行完成后的验收条件。
class DebugTestCaseAssertions {
  /// 允许的最终 turn 状态集合。
  final List<String> endStatus;

  /// 必须出现的事件名。
  final List<String> mustContainEvents;

  /// 不得出现的事件名。
  final List<String> mustNotContainEvents;

  /// 必须全部出现的错误码。
  final List<String> mustContainErrorCodes;

  /// 至少出现一个即可的错误码。
  final List<String> mustContainAnyErrorCodes;

  /// 禁止出现的错误码。
  final List<String> forbidErrorCodes;

  /// 最终回答中必须包含的文本片段。
  final List<String> finalAnswerContainsAll;

  /// 指定文件最终必须包含的文本片段。
  final List<DebugTestCaseFileExpectation> finalFileContains;

  /// 指定文件最终不应发生改动。
  final List<String> finalFileUnchanged;

  /// 不允许错误地宣称写入成功。
  final bool mustNotFalseClaimWriteSuccess;

  /// 不允许错误地宣称读取成功。
  final bool mustNotFalseClaimReadSuccess;

  /// 不允许出现挂起不结束的情况。
  final bool mustNotHang;

  const DebugTestCaseAssertions({
    required this.endStatus,
    required this.mustContainEvents,
    required this.mustNotContainEvents,
    required this.mustContainErrorCodes,
    required this.mustContainAnyErrorCodes,
    required this.forbidErrorCodes,
    required this.finalAnswerContainsAll,
    required this.finalFileContains,
    required this.finalFileUnchanged,
    required this.mustNotFalseClaimWriteSuccess,
    required this.mustNotFalseClaimReadSuccess,
    required this.mustNotHang,
  });

  factory DebugTestCaseAssertions.fromJson(
    Map<String, dynamic> json, {
    required String caseId,
  }) {
    final scope = 'DebugTestCase.$caseId.assertions';
    final endStatus = _readStringList(
      json['endStatus'],
      fieldName: '$scope.endStatus',
      allowEmpty: false,
      dedupe: true,
    );
    for (final status in endStatus) {
      if (!kDebugCaseAllowedEndStatuses.contains(status)) {
        throw FormatException('$scope.endStatus 包含不支持的状态: $status');
      }
    }

    final finalFileContains = _readObjectList(
      json['finalFileContains'],
      fieldName: '$scope.finalFileContains',
      allowMissing: true,
    ).asMap().entries.map((entry) {
      return DebugTestCaseFileExpectation.fromJson(
        entry.value,
        scope: '$scope.finalFileContains[${entry.key}]',
      );
    }).toList(growable: false);

    return DebugTestCaseAssertions(
      endStatus: endStatus,
      mustContainEvents: _readStringList(
        json['mustContainEvents'],
        fieldName: '$scope.mustContainEvents',
        allowEmpty: true,
        allowMissing: true,
        dedupe: true,
      ),
      mustNotContainEvents: _readStringList(
        json['mustNotContainEvents'],
        fieldName: '$scope.mustNotContainEvents',
        allowEmpty: true,
        allowMissing: true,
        dedupe: true,
      ),
      mustContainErrorCodes: _readStringList(
        json['mustContainErrorCodes'],
        fieldName: '$scope.mustContainErrorCodes',
        allowEmpty: true,
        allowMissing: true,
        dedupe: true,
      ),
      mustContainAnyErrorCodes: _readStringList(
        json['mustContainAnyErrorCodes'],
        fieldName: '$scope.mustContainAnyErrorCodes',
        allowEmpty: true,
        allowMissing: true,
        dedupe: true,
      ),
      forbidErrorCodes: _readStringList(
        json['forbidErrorCodes'],
        fieldName: '$scope.forbidErrorCodes',
        allowEmpty: true,
        allowMissing: true,
        dedupe: true,
      ),
      finalAnswerContainsAll: _readStringList(
        json['finalAnswerContainsAll'],
        fieldName: '$scope.finalAnswerContainsAll',
        allowEmpty: true,
        allowMissing: true,
        dedupe: true,
      ),
      finalFileContains: finalFileContains,
      finalFileUnchanged: _readStringList(
        json['finalFileUnchanged'],
        fieldName: '$scope.finalFileUnchanged',
        allowEmpty: true,
        allowMissing: true,
        dedupe: true,
      ),
      mustNotFalseClaimWriteSuccess:
          json['mustNotFalseClaimWriteSuccess'] == true,
      mustNotFalseClaimReadSuccess:
          json['mustNotFalseClaimReadSuccess'] == true,
      mustNotHang: json['mustNotHang'] == true,
    );
  }
}

/// 文件内容断言。
class DebugTestCaseFileExpectation {
  /// 文件相对路径。
  final String path;

  /// 文件最终必须包含的文本。
  final String text;

  const DebugTestCaseFileExpectation({
    required this.path,
    required this.text,
  });

  factory DebugTestCaseFileExpectation.fromJson(
    Map<String, dynamic> json, {
    required String scope,
  }) {
    final path = _readRequiredString(json, 'path', scope: scope);
    _validateRelativePath(path, fieldName: '$scope.path');
    return DebugTestCaseFileExpectation(
      path: path,
      text: _readRequiredString(json, 'text', scope: scope),
    );
  }
}

/// Debug 案例库根对象。
class DebugTestCaseLibrary {
  /// 已过滤 `enabled == false` 后的可用案例列表。
  final List<DebugTestCase> allCases;

  const DebugTestCaseLibrary({
    required this.allCases,
  });

  /// 空状态等轻入口使用的精选案例。
  List<DebugTestCase> get featuredCases =>
      allCases.where((item) => item.featured).toList(growable: false);
}

const Set<String> kDebugCaseAllowedHistoryRoles = {
  'user',
  'assistant',
  'system',
};

const Set<String> kDebugCaseAllowedEndStatuses = {
  'completed',
  'failed',
  'cancelled',
  'awaitingToolConfirmation',
  'awaitingUserInteraction',
};

final RegExp kDebugCaseToolCheckpointPattern = RegExp(
  r'^tool:[A-Za-z_][A-Za-z0-9_]*:(success|failure|awaiting_confirmation)$',
);

String _readRequiredString(
  Map<String, dynamic> json,
  String key, {
  required String scope,
}) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$scope.$key 必须是非空字符串');
  }
  return value.trim();
}

Map<String, dynamic> _readObject(
  Map<String, dynamic> json,
  String key, {
  required String scope,
}) {
  final value = json[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('$scope.$key 必须是对象');
  }
  return value;
}

List<Map<String, dynamic>> _readObjectList(
  dynamic raw, {
  required String fieldName,
  bool allowMissing = false,
}) {
  if (raw == null && allowMissing) {
    return const [];
  }
  if (raw is! List) {
    throw FormatException('$fieldName 必须是数组');
  }
  return raw.map((item) {
    if (item is! Map<String, dynamic>) {
      throw FormatException('$fieldName 元素必须是对象');
    }
    return item;
  }).toList(growable: false);
}

List<String> _readStringList(
  dynamic raw, {
  required String fieldName,
  required bool allowEmpty,
  bool allowMissing = false,
  bool dedupe = false,
}) {
  if (raw == null && allowMissing) {
    return const [];
  }
  if (raw is! List) {
    throw FormatException('$fieldName 必须是数组');
  }
  final values = raw.map((item) {
    if (item is! String || item.trim().isEmpty) {
      throw FormatException('$fieldName 元素必须是非空字符串');
    }
    return item.trim();
  }).toList(growable: false);
  if (!allowEmpty && values.isEmpty) {
    throw FormatException('$fieldName 不能为空');
  }
  if (!dedupe) {
    return values;
  }
  return values.toSet().toList(growable: false);
}

List<String> _readCheckpointList(
  dynamic raw, {
  required String fieldName,
}) {
  final values = _readStringList(
    raw,
    fieldName: fieldName,
    allowEmpty: false,
  );
  for (final item in values) {
    final isSpecial =
        item == 'finalAnswer' ||
        item == 'askUser:prompted' ||
        item == 'askUser:answered';
    if (!isSpecial && !kDebugCaseToolCheckpointPattern.hasMatch(item)) {
      throw FormatException('$fieldName 包含非法 checkpoint: $item');
    }
  }
  return values;
}

void _validateRelativePath(String path, {required String fieldName}) {
  if (path.startsWith('/') || path.contains('..')) {
    throw FormatException('$fieldName 必须是沙箱相对路径');
  }
}
