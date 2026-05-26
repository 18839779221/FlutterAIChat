import 'package:ai_chat/services/debug/llm_cache_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses recent llm.request.done entries and computes hit rates',
      () async {
    final service = LlmCacheStatsService();
    final projection = await service.readFromLines(
      [
        '2026-05-26T10:00:00.000+08:00 INFO [trace] [ConfigurableHttpLLM] llm.request.done apiStyle=responses inputTokens=100 cachedInputTokens=60 totalMs=900',
        '2026-05-26T10:00:01.000+08:00 INFO [trace] [ConfigurableHttpLLM] llm.request.done apiStyle=chatCompletions inputTokens=50 totalMs=700',
      ],
      sampleSize: 50,
    );

    expect(projection.summary.totalRequests, 2);
    expect(projection.summary.requestsWithUsage, 2);
    expect(projection.summary.hitRequests, 1);
    expect(projection.summary.totalInputTokens, 150);
    expect(projection.summary.hitInputTokens, 60);
  });

  test('counts cacheReadInputTokens as hits and groups by apiStyle', () async {
    final service = LlmCacheStatsService();
    final projection = await service.readFromLines(
      [
        '2026-05-26T10:00:00.000+08:00 INFO [trace] [ConfigurableHttpLLM] llm.request.done apiStyle=anthropicMessages inputTokens=120 cacheReadInputTokens=90 totalMs=1000',
        '2026-05-26T10:00:01.000+08:00 INFO [trace] [ConfigurableHttpLLM] llm.request.done apiStyle=responses inputTokens=80 cachedInputTokens=20 totalMs=650',
      ],
      sampleSize: 50,
    );

    expect(projection.summary.hitRequests, 2);
    expect(projection.summary.hitInputTokens, 110);
    expect(projection.bucketsByApiStyle.map((bucket) => bucket.key), containsAll([
      'anthropicMessages',
      'responses',
    ]));
  });

  test('ignores invalid lines and keeps only recent matching requests', () async {
    final service = LlmCacheStatsService();
    final projection = await service.readFromLines(
      [
        'bad line',
        '2026-05-26T10:00:00.000+08:00 INFO [runtime] [ConfigurableHttpLLM] llm.request.done apiStyle=responses inputTokens=100 cachedInputTokens=10',
        '2026-05-26T10:00:01.000+08:00 INFO [trace] [ConfigurableHttpLLM] llm.request.done apiStyle=responses inputTokens=50 cachedInputTokens=20',
        '2026-05-26T10:00:02.000+08:00 INFO [trace] [ConfigurableHttpLLM] llm.request.done apiStyle=responses inputTokens=60 cachedInputTokens=30',
      ],
      sampleSize: 1,
    );

    expect(projection.summary.totalRequests, 1);
    expect(projection.recentRequests.single.inputTokens, 60);
    expect(projection.recentRequests.single.cachedInputTokens, 30);
  });

  test('returns warning when no usage is available', () async {
    final service = LlmCacheStatsService();
    final projection = await service.readFromLines(
      [
        '2026-05-26T10:00:01.000+08:00 INFO [trace] [ConfigurableHttpLLM] llm.request.done apiStyle=responses estimatedInputTokens=88 totalMs=700 cacheStrategy=observeOnly',
      ],
      sampleSize: 50,
    );

    expect(projection.summary.totalRequests, 1);
    expect(projection.summary.requestsWithUsage, 0);
    expect(projection.recentRequests.single.estimatedInputTokens, 88);
    expect(projection.warningMessage, isNotNull);
  });

  test('returns warning when log file path is unavailable', () async {
    final service = LlmCacheStatsService(logFilePathProvider: () => null);
    final projection = await service.readRecentStats();

    expect(projection.summary.totalRequests, 0);
    expect(projection.warningMessage, contains('当前平台无本地日志文件'));
  });
}
