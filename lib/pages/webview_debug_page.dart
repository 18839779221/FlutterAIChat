import 'dart:async';
import 'dart:io';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// WebView 动态加载调试页面
class WebviewDebugPage extends StatefulWidget {
  const WebviewDebugPage({
    super.key,
    this.appSupportDirectoryProvider = getApplicationSupportDirectory,
    this.nowProvider = DateTime.now,
    this.enableLiveClock = true,
  });

  final Future<Directory> Function() appSupportDirectoryProvider;
  final DateTime Function() nowProvider;
  final bool enableLiveClock;

  @override
  State<WebviewDebugPage> createState() => _WebviewDebugPageState();
}

enum _StreamSpeed {
  slow(Duration(seconds: 24), '慢速'),
  normal(Duration(seconds: 8), '正常'),
  fast(Duration(seconds: 3), '快速');

  final Duration totalPlaybackDuration;
  final String label;
  const _StreamSpeed(this.totalPlaybackDuration, this.label);
}

class _WebviewDebugPageState extends State<WebviewDebugPage> {
  String _currentSource = '';
  bool _isStreaming = false;
  bool _streamingCompleted = false;
  Timer? _streamTimer;
  int _streamIndex = 0;
  List<WebviewDebugArtifactFile> _artifactFiles = [];
  bool _isLoading = true;
  int _selectedFileIndex = 0;
  _StreamSpeed _streamSpeed = _StreamSpeed.normal;
  double _playbackDurationSeconds =
      _StreamSpeed.normal.totalPlaybackDuration.inMilliseconds / 1000;
  int _replayTargetLength = 0;
  Timer? _clockTimer;
  DateTime _clockTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTime = widget.nowProvider();
    if (widget.enableLiveClock) {
      _clockTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _clockTime = widget.nowProvider();
        });
      });
    }
    _loadArtifactFiles();
  }

  Future<void> _loadArtifactFiles() async {
    try {
      final appSupportDir = await widget.appSupportDirectoryProvider();
      final artifactsDir = Directory('${appSupportDir.path}/agent');
      final files = await discoverWebviewDebugArtifactFiles(artifactsDir);

      setState(() {
        _artifactFiles = files;
        _selectedFileIndex = 0;
        _replayTargetLength = _selectedArtifactLengthFor(files, 0);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _startStreaming() {
    if (_isStreaming) {
      return;
    }

    final selectedArtifact = _selectedArtifactFile;
    if (selectedArtifact == null) {
      return;
    }

    final targetLength = resolveWebviewDebugReplayTargetLength(
      _replayTargetLength,
      selectedArtifact.content.length,
    );
    final fullContent = resolveWebviewDebugReplaySource(
      artifactContent: selectedArtifact.content,
      targetLength: targetLength,
    );
    if (fullContent.isEmpty) {
      setState(() {
        _currentSource = '';
        _isStreaming = false;
        _streamingCompleted = true;
      });
      return;
    }

    const chunkCount = 8;
    final chunkSize = (fullContent.length / chunkCount).ceil();
    final totalPlaybackDuration = Duration(
      milliseconds: (_playbackDurationSeconds * 1000).round(),
    );
    final interval = resolveWebviewDebugStreamingInterval(
      totalPlaybackDuration: totalPlaybackDuration,
      chunkCount: chunkCount,
    );

    _streamTimer?.cancel();
    _streamTimer = null;

    debugPrint('[WebviewDebug] Starting stream: file=${selectedArtifact.name}, '
        'artifactPath=${selectedArtifact.path}, '
        'contentLength=${fullContent.length}, chunkSize=$chunkSize, speed=${_streamSpeed.label}, '
        'playbackSeconds=${_playbackDurationSeconds.toStringAsFixed(1)}, intervalMs=${interval.inMilliseconds}');

    setState(() {
      _isStreaming = true;
      _streamingCompleted = false;
      _streamIndex = chunkSize;
      _currentSource = fullContent.substring(0, chunkSize);
    });

    debugPrint('[WebviewDebug] Initial chunk set: sourceLength=${_currentSource.length}');

    _streamTimer = Timer.periodic(interval, (timer) {
      if (!mounted) {
        debugPrint('[WebviewDebug] Widget unmounted, canceling timer');
        timer.cancel();
        return;
      }

      final nextIndex = _streamIndex + chunkSize;
      if (nextIndex >= fullContent.length) {
        timer.cancel();
        _streamTimer = null;
        debugPrint('[WebviewDebug] Stream completed: finalLength=${fullContent.length}');
        if (mounted) {
          setState(() {
            _currentSource = fullContent;
            _isStreaming = false;
            _streamingCompleted = true;
            _streamIndex = fullContent.length;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _currentSource = fullContent.substring(0, nextIndex);
          _streamIndex = nextIndex;
        });
        debugPrint('[WebviewDebug] Stream update: sourceLength=${_currentSource.length}, progress=${(nextIndex / fullContent.length * 100).toStringAsFixed(1)}%');
      }
    });
  }

  void _stopStreaming() {
    _streamTimer?.cancel();
    _streamTimer = null;
    if (mounted) {
      setState(() {
        _isStreaming = false;
        _streamingCompleted = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView 动态加载调试'),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    spacing.lg,
                    spacing.lg + 44,
                    spacing.lg,
                    spacing.lg,
                  ),
                  children: [
                    _buildControlPanel(colors, spacing),
                    if (_artifactFiles.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: spacing.md),
                        child: Text(
                          '当前未发现已有 artifact。请先确认应用私有目录下 `agent/workspaces/.../artifacts` 是否已有 HTML 或 SVG 文件。',
                          style: TextStyle(
                            color: colors.secondaryText,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    if (_isStreaming || _currentSource.isNotEmpty) ...[
                      SizedBox(height: spacing.lg),
                      _buildTopHint(colors, spacing),
                      SizedBox(height: spacing.md),
                      Builder(
                        builder: (context) {
                          debugPrint('[WebviewDebug] Rendering ArtifactPreviewSurface: '
                              'sourceLength=${_currentSource.length}, '
                              'isStreaming=$_isStreaming, '
                              'enableInternalScroll=true');
                          final activeLabel =
                              _selectedArtifactFile?.name ?? 'unknown-artifact';
                          final activeSourcePath =
                              _selectedArtifactFile?.path ?? 'debug://artifact';
                          return ArtifactPreviewSurface(
                            artifactId: 'debug-$activeLabel',
                            source: _currentSource,
                            sourcePath: activeSourcePath,
                            isRuntimePreview: _isStreaming,
                            enableInternalScroll: false,
                          );
                        },
                      ),
                      SizedBox(height: spacing.md),
                      if (_streamingCompleted) _buildBottomHint(colors, spacing),
                    ] else
                      Builder(
                        builder: (context) {
                          debugPrint('[WebviewDebug] Not rendering ArtifactPreviewSurface: '
                              'isStreaming=$_isStreaming, '
                              'sourceEmpty=${_currentSource.isEmpty}');
                          return const SizedBox.shrink();
                        },
                      ),
                  ],
                ),
          Positioned(
            top: spacing.sm,
            left: spacing.lg,
            right: spacing.lg,
            child: IgnorePointer(
              child: _buildClockBanner(colors),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(AppThemeSpec colors, AppSpacing spacing) {
    final selectedArtifact = _selectedArtifactFile;
    final selectedArtifactLength = selectedArtifact?.content.length ?? 0;
    final selectedReplayTargetLength = resolveWebviewDebugReplayTargetLength(
      _replayTargetLength,
      selectedArtifactLength,
    );

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.settingsPanelBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择 Artifact 文件',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          SizedBox(height: spacing.sm),
          DropdownButton<int>(
            value: _selectedFileIndex < _artifactFiles.length
                ? _selectedFileIndex
                : (_artifactFiles.isEmpty ? null : 0),
            isExpanded: true,
            items: List.generate(_artifactFiles.length, (index) {
              return DropdownMenuItem(
                value: index,
                child: Text(
                  _artifactFiles[index].name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
            onChanged: _isStreaming
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _selectedFileIndex = value;
                        _replayTargetLength = _selectedArtifactLengthFor(
                          _artifactFiles,
                          value,
                        );
                        _currentSource = '';
                        _streamingCompleted = false;
                      });
                    }
                  },
          ),
          if (selectedArtifact != null) ...[
            SizedBox(height: spacing.sm),
            Text(
              '文件路径: ${selectedArtifact.path}',
              style: TextStyle(
                fontSize: 12,
                color: colors.secondaryText,
                height: 1.4,
              ),
            ),
          ],
          SizedBox(height: spacing.md),
          Text(
            'HTML 渲染字符数 $selectedReplayTargetLength / $selectedArtifactLength',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          Slider(
            value: selectedReplayTargetLength.toDouble(),
            min: 0,
            max: selectedArtifactLength > 0
                ? selectedArtifactLength.toDouble()
                : 1,
            divisions: selectedArtifactLength > 0 ? selectedArtifactLength : 1,
            label: '$selectedReplayTargetLength chars',
            onChanged: _isStreaming || selectedArtifact == null
                ? null
                : (value) {
                    setState(() {
                      _replayTargetLength =
                          resolveWebviewDebugReplayTargetLength(
                            value.round(),
                            selectedArtifact.content.length,
                          );
                    });
                  },
          ),
          SizedBox(height: spacing.md),
          Text(
            '流式速度',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.xs,
            children: _StreamSpeed.values.map((speed) {
              return ChoiceChip(
                label: Text(speed.label),
                selected: _streamSpeed == speed,
                onSelected: _isStreaming
                    ? null
                    : (selected) {
                        if (selected) {
                          setState(() {
                            _streamSpeed = speed;
                            _playbackDurationSeconds =
                                speed.totalPlaybackDuration.inMilliseconds /
                                    1000;
                          });
                        }
                      },
              );
            }).toList(),
          ),
          SizedBox(height: spacing.md),
          Text(
            '总播放时长 ${_playbackDurationSeconds.toStringAsFixed(1)}s',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          Slider(
            value: _playbackDurationSeconds,
            min: 2,
            max: 60,
            divisions: 58,
            label: '${_playbackDurationSeconds.toStringAsFixed(1)}s',
            onChanged: _isStreaming
                ? null
                : (value) {
                    setState(() {
                      _playbackDurationSeconds = value;
                    });
                  },
          ),
          SizedBox(height: spacing.md),
          Row(
            children: [
              FilledButton.icon(
                onPressed:
                    _isStreaming || _selectedArtifactFile == null
                        ? null
                        : _startStreaming,
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始流式传输'),
              ),
              SizedBox(width: spacing.sm),
              if (_isStreaming)
                OutlinedButton.icon(
                  onPressed: _stopStreaming,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopHint(AppThemeSpec colors, AppSpacing spacing) {
    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.assistantSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '正在回放真实 artifact 的 source 递增过程；结束后会切到最终 takeover，便于直接观察 runtime preview 阶段本身是否存在高度跳变或文字拉伸。',
        style: TextStyle(
          fontSize: 13,
          color: colors.secondaryText,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildBottomHint(AppThemeSpec colors, AppSpacing spacing) {
    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.assistantSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '✓ 流式传输已完成，内容已全部加载',
        style: TextStyle(
          fontSize: 13,
          color: colors.primaryText,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildClockBanner(AppThemeSpec colors) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        key: const Key('webview-debug-clock-banner'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.assistantSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.settingsPanelBackground),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, 4),
              color: Color(0x22000000),
            ),
          ],
        ),
        child: Text(
          _formatClockTime(_clockTime),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  WebviewDebugArtifactFile? get _selectedArtifactFile {
    if (_artifactFiles.isEmpty) {
      return null;
    }
    if (_selectedFileIndex < 0 || _selectedFileIndex >= _artifactFiles.length) {
      return _artifactFiles.first;
    }
    return _artifactFiles[_selectedFileIndex];
  }

  int _selectedArtifactLengthFor(
    List<WebviewDebugArtifactFile> files,
    int index,
  ) {
    if (files.isEmpty) {
      return 0;
    }
    final safeIndex = index.clamp(0, files.length - 1);
    return files[safeIndex].content.length;
  }

  String _formatClockTime(DateTime time) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    String threeDigits(int value) => value.toString().padLeft(3, '0');

    return '${twoDigits(time.hour)}:${twoDigits(time.minute)}:${twoDigits(time.second)}.${threeDigits(time.millisecond)}';
  }
}

@visibleForTesting
Future<List<WebviewDebugArtifactFile>> discoverWebviewDebugArtifactFiles(
  Directory rootDirectory,
) async {
  if (!await rootDirectory.exists()) {
    return const <WebviewDebugArtifactFile>[];
  }

  final files = <WebviewDebugArtifactFile>[];
  await for (final entity in rootDirectory.list(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    if (!entity.path.endsWith('.html') && !entity.path.endsWith('.svg')) {
      continue;
    }
    final content = await entity.readAsString();
    files.add(WebviewDebugArtifactFile(
      name: entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : entity.path.split('/').last,
      content: content,
      path: entity.path,
    ));
  }
  files.sort((a, b) => a.name.compareTo(b.name));
  return files;
}

class WebviewDebugArtifactFile {
  final String name;
  final String content;
  final String path;

  const WebviewDebugArtifactFile({
    required this.name,
    required this.content,
    required this.path,
  });
}

@visibleForTesting
int resolveWebviewDebugReplayTargetLength(int rawValue, int sourceLength) {
  return rawValue.clamp(0, sourceLength);
}

@visibleForTesting
String resolveWebviewDebugReplaySource({
  required String artifactContent,
  required int targetLength,
}) {
  final safeLength = resolveWebviewDebugReplayTargetLength(
    targetLength,
    artifactContent.length,
  );
  if (safeLength >= artifactContent.length) {
    return artifactContent;
  }
  return artifactContent.substring(0, safeLength);
}

@visibleForTesting
Duration resolveWebviewDebugStreamingInterval({
  required Duration totalPlaybackDuration,
  required int chunkCount,
}) {
  if (chunkCount <= 0) {
    return totalPlaybackDuration;
  }
  final milliseconds =
      (totalPlaybackDuration.inMilliseconds / chunkCount).round();
  return Duration(milliseconds: milliseconds.clamp(1, 600000));
}
