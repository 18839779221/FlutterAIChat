import 'dart:async';

import 'package:flutter/foundation.dart';

import 'log_file_sink.dart';
import 'log_file_sink_base.dart';

/// 日志用途分类。
enum LogKind {
  runtime,
  trace,
  temp,
}

/// 日志级别。
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

extension on LogLevel {
  String get label {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }
}

/// 应用统一日志入口。
///
/// - `runtime`：正式运行日志，默认同时输出控制台，原生平台追加写入本地文件
/// - `trace`：关键链路观察日志，用于 turn/tool/planner/LLM 链路排障
/// - `temp`：临时调试日志，必须显式调用，方便后续检索和清理
class Logger {
  static LogFileSink? _fileSink;
  static bool _initialized = false;
  static String? _sessionId;

  /// 当前原生日志文件路径；Web 环境下为 `null`。
  static String? get logFilePath => _fileSink?.filePath;

  /// 初始化日志系统。
  ///
  /// 原生平台会准备 `logs/app.log`；Web 仅保留控制台输出。
  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _sessionId = _newSessionId();
    _fileSink = await createLogFileSink();
    runtime(
      'AppRun',
      'app_run.start',
      data: {
        'sessionId': _sessionId,
        if (_fileSink != null) 'logFile': _fileSink!.filePath,
        if (_fileSink == null) 'mode': 'console_only',
      },
    );
  }

  static void d(String tag, String message) {
    runtime(tag, message, level: LogLevel.debug);
  }

  static void i(String tag, String message) {
    runtime(tag, message);
  }

  static void w(String tag, String message) {
    runtime(tag, message, level: LogLevel.warning);
  }

  static void e(String tag, String message, [dynamic error]) {
    runtime(
      tag,
      error == null ? message : '$message error=${_stringify(error)}',
      level: LogLevel.error,
    );
  }

  static void runtime(
    String tag,
    String message, {
    LogLevel level = LogLevel.info,
    Map<String, dynamic>? data,
  }) {
    _log(
      kind: LogKind.runtime,
      level: level,
      tag: tag,
      message: message,
      data: data,
    );
  }

  static void trace(
    String tag,
    String message, {
    LogLevel level = LogLevel.info,
    Map<String, dynamic>? data,
  }) {
    _log(
      kind: LogKind.trace,
      level: level,
      tag: tag,
      message: message,
      data: data,
    );
  }

  static void temp(
    String tag,
    String message, {
    LogLevel level = LogLevel.debug,
    String? reason,
    Map<String, dynamic>? data,
  }) {
    final payload = <String, dynamic>{
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      ...?data,
    };
    _log(
      kind: LogKind.temp,
      level: level,
      tag: tag,
      message: message,
      data: payload.isEmpty ? null : payload,
    );
  }

  static void _log({
    required LogKind kind,
    required LogLevel level,
    required String tag,
    required String message,
    Map<String, dynamic>? data,
  }) {
    final line = _formatLine(
      timestamp: DateTime.now().toUtc(),
      kind: kind,
      level: level,
      tag: tag,
      message: message,
      data: data,
    );
    debugPrint(line);
    unawaited(_fileSink?.writeLine(line));
  }

  static String _formatLine({
    required DateTime timestamp,
    required LogKind kind,
    required LogLevel level,
    required String tag,
    required String message,
    Map<String, dynamic>? data,
  }) {
    final buffer = StringBuffer()
      ..write(timestamp.toIso8601String())
      ..write(' ')
      ..write(level.label)
      ..write(' [')
      ..write(kind.name)
      ..write('] [')
      ..write(tag)
      ..write('] ')
      ..write(_normalize(message));

    final payload = <String, dynamic>{
      if ((_sessionId ?? '').isNotEmpty) 'sessionId': _sessionId,
      ...?data,
    };
    final suffix = _formatKeyValues(payload);
    if (suffix.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(suffix);
    }
    return buffer.toString();
  }

  static String _formatKeyValues(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return '';
    }

    final parts = <String>[];
    data.forEach((key, value) {
      if (value == null) {
        return;
      }
      parts.add('$key=${_formatValue(value)}');
    });
    return parts.join(' ');
  }

  static String _formatValue(dynamic value) {
    if (value is List) {
      final items = value.map(_formatValue).join(',');
      return '[${_truncate(items)}]';
    }
    if (value is Map<String, dynamic>) {
      final entries = value.entries
          .map((entry) => '${entry.key}:${_formatValue(entry.value)}')
          .join(',');
      return '{${_truncate(entries)}}';
    }
    return _truncate(_normalize(_stringify(value)));
  }

  static String _stringify(dynamic value) {
    if (value is StackTrace) {
      return value.toString();
    }
    return '$value';
  }

  static String _normalize(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _truncate(String value, {int maxLength = 240}) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength - 3)}...';
  }

  static String _newSessionId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'run_$timestamp';
  }
}
