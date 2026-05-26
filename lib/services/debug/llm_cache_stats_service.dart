import 'dart:io';

import 'package:ai_chat/models/debug/debug_cache_panel_projection.dart';
import 'package:ai_chat/models/debug/llm_cache_request_record.dart';
import 'package:ai_chat/models/debug/llm_cache_stats_bucket.dart';
import 'package:ai_chat/models/debug/llm_cache_stats_summary.dart';
import 'package:ai_chat/utils/logger.dart';

typedef LogFilePathProvider = String? Function();

/// Builds cache hit rate statistics by parsing `llm.request.done` trace logs.
class LlmCacheStatsService {
  LlmCacheStatsService({
    LogFilePathProvider? logFilePathProvider,
  }) : _logFilePathProvider = logFilePathProvider ?? (() => Logger.logFilePath);

  final LogFilePathProvider _logFilePathProvider;

  Future<DebugCachePanelProjection> readRecentStats({
    int sampleSize = 100,
  }) async {
    final logFilePath = _logFilePathProvider();
    if (logFilePath == null || logFilePath.trim().isEmpty) {
      return _buildProjection(
        const <LlmCacheRequestRecord>[],
        sampleSize: sampleSize,
        sourceLogPath: logFilePath,
        warningMessage: '当前平台无本地日志文件',
      );
    }

    final file = File(logFilePath);
    if (!await file.exists()) {
      return _buildProjection(
        const <LlmCacheRequestRecord>[],
        sampleSize: sampleSize,
        sourceLogPath: logFilePath,
        warningMessage: '缓存统计日志文件不存在',
      );
    }

    final lines = await file.readAsLines();
    return readFromLines(
      lines,
      sampleSize: sampleSize,
      sourceLogPath: logFilePath,
    );
  }

  Future<DebugCachePanelProjection> readFromLines(
    List<String> lines, {
    int sampleSize = 100,
    String? sourceLogPath,
  }) async {
    final records = <LlmCacheRequestRecord>[];
    for (final line in lines.reversed) {
      final record = _parseLine(line);
      if (record == null) {
        continue;
      }
      records.add(record);
      if (records.length >= sampleSize) {
        break;
      }
    }

    return _buildProjection(
      records,
      sampleSize: sampleSize,
      sourceLogPath: sourceLogPath,
    );
  }

  DebugCachePanelProjection _buildProjection(
    List<LlmCacheRequestRecord> recentRequests, {
    required int sampleSize,
    required String? sourceLogPath,
    String? warningMessage,
  }) {
    final chronological = recentRequests.reversed.toList(growable: false);
    final summary = _buildSummary(chronological);
    final bucketsByApiStyle = _buildBucketsByApiStyle(chronological);
    var effectiveWarning = warningMessage;
    if (effectiveWarning == null && chronological.isEmpty) {
      effectiveWarning = 'No cache request samples found.';
    } else if (effectiveWarning == null && summary.requestsWithUsage == 0) {
      effectiveWarning = '当前样本中无可用 usage，无法计算完整命中率';
    }

    return DebugCachePanelProjection(
      sampleSize: sampleSize,
      sourceLogPath: sourceLogPath,
      summary: summary,
      bucketsByApiStyle: bucketsByApiStyle,
      recentRequests: chronological,
      warningMessage: effectiveWarning,
    );
  }

  LlmCacheStatsSummary _buildSummary(List<LlmCacheRequestRecord> records) {
    var totalRequests = 0;
    var requestsWithUsage = 0;
    var hitRequests = 0;
    var totalInputTokens = 0;
    var hitInputTokens = 0;
    for (final record in records) {
      totalRequests += 1;
      final inputTokens = record.inputTokens;
      final readTokens =
          (record.cachedInputTokens ?? 0) + (record.cacheReadInputTokens ?? 0);
      final hasUsage = inputTokens != null;
      if (hasUsage) {
        requestsWithUsage += 1;
        totalInputTokens += inputTokens;
      }
      if (readTokens > 0) {
        hitRequests += 1;
        hitInputTokens += readTokens;
      }
    }
    return LlmCacheStatsSummary(
      totalRequests: totalRequests,
      requestsWithUsage: requestsWithUsage,
      hitRequests: hitRequests,
      totalInputTokens: totalInputTokens,
      hitInputTokens: hitInputTokens,
    );
  }

  List<LlmCacheStatsBucket> _buildBucketsByApiStyle(
    List<LlmCacheRequestRecord> records,
  ) {
    final grouped = <String, List<LlmCacheRequestRecord>>{};
    for (final record in records) {
      final key = (record.apiStyle ?? 'unknown').trim();
      grouped.putIfAbsent(key.isEmpty ? 'unknown' : key, () => []).add(record);
    }
    final buckets = grouped.entries
        .map(
          (entry) => LlmCacheStatsBucket(
            key: entry.key,
            summary: _buildSummary(entry.value),
          ),
        )
        .toList(growable: false);
    buckets.sort((left, right) => right.summary.totalRequests - left.summary.totalRequests);
    return buckets;
  }

  LlmCacheRequestRecord? _parseLine(String line) {
    if (!line.contains('[trace]') ||
        !line.contains('[ConfigurableHttpLLM]') ||
        !line.contains('llm.request.done')) {
      return null;
    }
    final firstSpace = line.indexOf(' ');
    if (firstSpace <= 0) {
      return null;
    }
    final timestampText = line.substring(0, firstSpace).trim();
    final timestamp = DateTime.tryParse(timestampText);
    if (timestamp == null) {
      return null;
    }

    final markerIndex = line.indexOf('llm.request.done');
    if (markerIndex == -1) {
      return null;
    }
    final payload = line.substring(markerIndex + 'llm.request.done'.length).trim();
    final values = _parseKeyValues(payload);
    return LlmCacheRequestRecord(
      timestamp: timestamp,
      apiStyle: values['apiStyle'],
      modelName: values['model'],
      purpose: values['purpose'],
      cacheStrategy: values['cacheStrategy'],
      estimatedInputTokens: _tryParseInt(values['estimatedInputTokens']),
      inputTokens: _tryParseInt(values['inputTokens']),
      cachedInputTokens: _tryParseInt(values['cachedInputTokens']),
      cacheReadInputTokens: _tryParseInt(values['cacheReadInputTokens']),
      cacheWriteInputTokens: _tryParseInt(values['cacheWriteInputTokens']),
      cacheMissInputTokens: _tryParseInt(values['cacheMissInputTokens']),
      totalMs: _tryParseInt(values['totalMs']),
      firstChunkMs: _tryParseInt(values['firstChunkMs']),
    );
  }

  Map<String, String> _parseKeyValues(String payload) {
    final result = <String, String>{};
    final matches = RegExp(r'([A-Za-z0-9_.-]+)=([^\s]+)').allMatches(payload);
    for (final match in matches) {
      final key = match.group(1);
      final value = match.group(2);
      if (key == null || value == null) {
        continue;
      }
      result[key] = value;
    }
    return result;
  }

  int? _tryParseInt(String? value) {
    if (value == null) {
      return null;
    }
    return int.tryParse(value.trim());
  }
}
