import 'dart:convert';

import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_result.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

class ReadToolHandler implements ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'Read',
        title: 'Read',
        localizedTitle: LocalizedToolText(chinese: '读取文件', english: 'Read'),
        descriptionForModel:
            'Use this when you already know the target file path and need to inspect file contents. Supports pagination with offset and limit. Usually locate files with LS, Glob, or Grep first, then use Read. Before Edit or Write on an existing file, usually Read first.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Use this when you already know the target file path and need to inspect file contents. Supports pagination with offset and limit. Usually locate files with LS, Glob, or Grep first, then use Read. Before Edit or Write on an existing file, usually Read first.',
          chinese:
              '当你已经知道目标文件路径，并且需要查看文件内容时使用。支持 offset 和 limit 分页。通常应先用 LS、Glob 或 Grep 定位文件，再用 Read 查看内容。对已有文件执行 Edit 或 Write 前，通常应先 Read。',
        ),
        isConcurrencySafe: true,
        supportedPlatforms: ['android', 'ios', 'macos', 'windows', 'linux'],
        argumentSchema: ToolArgumentSchema(
          properties: {
            'file_path': ToolArgumentProperty.string(
              description: 'Relative sandbox file path to read.',
              localizedDescription: LocalizedToolText(
                english: 'Relative sandbox file path to read.',
                chinese: '要读取的沙箱相对文件路径。',
              ),
            ),
            'offset': ToolArgumentProperty.integer(
              description:
                  'Line offset to start reading from; 0 means the first line.',
              localizedDescription: LocalizedToolText(
                english:
                    'Line offset to start reading from; 0 means the first line.',
                chinese: '从第几行开始读取，0 表示文件第一行。',
              ),
            ),
            'limit': ToolArgumentProperty.integer(
              description: 'Maximum number of lines to return for pagination.',
              localizedDescription: LocalizedToolText(
                english:
                    'Maximum number of lines to return for pagination.',
                chinese: '最多返回多少行，用于分页读取。',
              ),
            ),
          },
          required: ['file_path'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final filePath = rawArguments['file_path'];
    if (filePath is! String || filePath.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_file_path',
        errorSummary: 'Read failed: missing file_path',
      );
    }

    final offset = rawArguments['offset'];
    final limit = rawArguments['limit'];
    return ToolArgumentResolution.valid({
      'file_path': filePath.trim(),
      'offset': offset is num ? offset.toInt().clamp(0, 1 << 31) : 0,
      if (limit is num) 'limit': limit.toInt().clamp(1, 5000),
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final fileTools = context.hostAdapters.fileTools;
    if (fileTools == null) {
      return const ToolResult(
        toolName: 'Read',
        status: ToolExecutionStatus.failure,
        summary: 'Read failed: file tool adapters unavailable',
        errorMessage: 'unsupported_tool',
      );
    }

    final resolution = fileTools.pathPolicy.normalizeSandboxPath(
      context.arguments['file_path'] as String,
    );
    if (!resolution.isValid || resolution.relativePath == null) {
      return ToolResult(
        toolName: 'Read',
        status: ToolExecutionStatus.failure,
        summary: 'Read failed: invalid file path',
        errorMessage: resolution.errorCode ?? 'invalid_file_path',
      );
    }

    final file = fileTools.rootService.resolveFile(resolution.relativePath!);
    if (!file.existsSync()) {
      return ToolResult(
        toolName: 'Read',
        status: ToolExecutionStatus.failure,
        summary: 'Read failed: file not found',
        data: {
          'filePath': resolution.relativePath,
          'message':
              'Read failed: file not found\n实际文件路径：${resolution.relativePath}',
        },
        errorMessage: 'file_not_found',
      );
    }

    final bytes = await file.readAsBytes();
    if (_looksBinary(bytes)) {
      return const ToolResult(
        toolName: 'Read',
        status: ToolExecutionStatus.failure,
        summary: 'Read failed: binary file is not supported',
        errorMessage: 'binary_file_not_supported',
      );
    }

    late final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return const ToolResult(
        toolName: 'Read',
        status: ToolExecutionStatus.failure,
        summary: 'Read failed: invalid UTF-8 content',
        errorMessage: 'invalid_utf8',
      );
    }

    final lines = const LineSplitter().convert(text);
    final offset = context.arguments['offset'] as int? ?? 0;
    final limit = context.arguments['limit'] as int?;
    final startIndex = offset.clamp(0, lines.length);
    final endIndex = limit == null
        ? lines.length
        : (startIndex + limit).clamp(0, lines.length);
    final selectedLines = lines.sublist(startIndex, endIndex);
    final budgetResult = fileTools.budgetService.apply(selectedLines);
    final formatted = fileTools.readFormatter.format(
      filePath: resolution.relativePath!,
      lines: budgetResult.lines,
      startLine: startIndex + 1,
      totalLines: lines.length,
      truncated: budgetResult.truncated || endIndex < lines.length,
    );

    final version = fileTools.sessionGuard.snapshotForStat(await file.stat());
    fileTools.sessionGuard.markRead(
      filePath: resolution.relativePath!,
      version: version,
    );

    return ToolResult(
      toolName: 'Read',
      status: ToolExecutionStatus.success,
      summary: '已读取文件：${resolution.relativePath}',
      data: {
        'filePath': resolution.relativePath,
        'message': '已读取文件：${resolution.relativePath}',
        ...formatted.toJson(),
        'fileVersion': version.toJson(),
      },
    );
  }


  bool _looksBinary(List<int> bytes) {
    for (final byte in bytes.take(512)) {
      if (byte == 0) {
        return true;
      }
    }
    return false;
  }
}
