import 'dart:async';
import 'dart:io';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// WebView 动态加载调试页面
class WebviewDebugPage extends StatefulWidget {
  const WebviewDebugPage({super.key});

  @override
  State<WebviewDebugPage> createState() => _WebviewDebugPageState();
}

enum _StreamSpeed {
  slow(Duration(milliseconds: 500), '慢速'),
  normal(Duration(milliseconds: 200), '正常'),
  fast(Duration(milliseconds: 50), '快速');

  final Duration interval;
  final String label;
  const _StreamSpeed(this.interval, this.label);
}

class _WebviewDebugPageState extends State<WebviewDebugPage> {
  String _currentSource = '';
  bool _isStreaming = false;
  bool _streamingCompleted = false;
  Timer? _streamTimer;
  int _streamIndex = 0;
  List<_ArtifactFile> _artifactFiles = [];
  bool _isLoading = true;
  int _selectedFileIndex = 0;
  _StreamSpeed _streamSpeed = _StreamSpeed.normal;

  @override
  void initState() {
    super.initState();
    _loadArtifactFiles();
  }

  Future<void> _loadArtifactFiles() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final artifactsDir = Directory('${appSupportDir.path}/inline_artifacts');

      if (!await artifactsDir.exists()) {
        setState(() => _isLoading = false);
        return;
      }

      final files = <_ArtifactFile>[];
      await for (final entity in artifactsDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.html')) {
          final content = await entity.readAsString();
          final name = entity.path.split('/').last;
          files.add(_ArtifactFile(
            name: name,
            content: content,
            path: entity.path,
          ));
        }
      }

      setState(() {
        _artifactFiles = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    super.dispose();
  }

  void _startStreaming() {
    if (_isStreaming || _artifactFiles.isEmpty) return;

    final fullContent = _artifactFiles[_selectedFileIndex].content;
    final chunkSize = (fullContent.length / 8).ceil();

    print('[WebviewDebug] Starting stream: file=${_artifactFiles[_selectedFileIndex].name}, '
        'contentLength=${fullContent.length}, chunkSize=$chunkSize, speed=${_streamSpeed.label}');

    setState(() {
      _isStreaming = true;
      _streamingCompleted = false;
      _streamIndex = chunkSize;
      _currentSource = fullContent.substring(0, chunkSize);
    });

    print('[WebviewDebug] Initial chunk set: sourceLength=${_currentSource.length}');

    _streamTimer = Timer.periodic(_streamSpeed.interval, (timer) {
      if (!mounted) {
        print('[WebviewDebug] Widget unmounted, canceling timer');
        timer.cancel();
        return;
      }

      final nextIndex = _streamIndex + chunkSize;
      if (nextIndex >= fullContent.length) {
        timer.cancel();
        print('[WebviewDebug] Stream completed: finalLength=${fullContent.length}');
        if (mounted) {
          setState(() {
            _currentSource = fullContent;
            _isStreaming = false;
            _streamingCompleted = true;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _currentSource = fullContent.substring(0, nextIndex);
          _streamIndex = nextIndex;
        });
        print('[WebviewDebug] Stream update: sourceLength=${_currentSource.length}, progress=${(nextIndex / fullContent.length * 100).toStringAsFixed(1)}%');
      }
    });
  }

  void _stopStreaming() {
    _streamTimer?.cancel();
    if (mounted) {
      setState(() => _isStreaming = false);
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _artifactFiles.isEmpty
              ? Center(
                  child: Text(
                    '未找到 artifact 文件\n请先在聊天中创建一些 artifact',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.secondaryText),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.all(spacing.lg),
                  children: [
                    _buildControlPanel(colors, spacing),
                    if (_isStreaming || _currentSource.isNotEmpty) ...[
                      SizedBox(height: spacing.lg),
                      _buildTopHint(colors, spacing),
                      SizedBox(height: spacing.md),
                      Builder(
                        builder: (context) {
                          print('[WebviewDebug] Rendering ArtifactPreviewSurface: '
                              'sourceLength=${_currentSource.length}, '
                              'isStreaming=$_isStreaming, '
                              'enableInternalScroll=true');
                          return ArtifactPreviewSurface(
                            artifactId:
                                'debug-${_artifactFiles[_selectedFileIndex].name}',
                            source: _currentSource,
                            sourcePath:
                                'debug-${_artifactFiles[_selectedFileIndex].name}',
                            enableInternalScroll: false,
                          );
                        },
                      ),
                      SizedBox(height: spacing.md),
                      if (_streamingCompleted) _buildBottomHint(colors, spacing),
                    ] else
                      Builder(
                        builder: (context) {
                          print('[WebviewDebug] Not rendering ArtifactPreviewSurface: '
                              'isStreaming=$_isStreaming, '
                              'sourceEmpty=${_currentSource.isEmpty}');
                          return const SizedBox.shrink();
                        },
                      ),
                  ],
                ),
    );
  }

  Widget _buildControlPanel(AppThemeSpec colors, AppSpacing spacing) {
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
            value: _selectedFileIndex,
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
                        _currentSource = '';
                        _streamingCompleted = false;
                      });
                    }
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
                          setState(() => _streamSpeed = speed);
                        }
                      },
              );
            }).toList(),
          ),
          SizedBox(height: spacing.md),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _isStreaming ? null : _startStreaming,
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
        '正在模拟流式传输 artifact 内容，观察 WebView 的渐进渲染效果',
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
}

class _ArtifactFile {
  final String name;
  final String content;
  final String path;

  const _ArtifactFile({
    required this.name,
    required this.content,
    required this.path,
  });
}
