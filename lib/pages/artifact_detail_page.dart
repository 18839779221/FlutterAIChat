import 'package:ai_chat/models/artifact/artifact_turn_projection.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class ArtifactDetailPage extends StatefulWidget {
  const ArtifactDetailPage({
    super.key,
    required this.projection,
  });

  final ArtifactTurnProjection projection;

  @override
  State<ArtifactDetailPage> createState() => _ArtifactDetailPageState();
}

class _ArtifactDetailPageState extends State<ArtifactDetailPage> {
  bool _showSource = false;

  Future<void> _copySource() async {
    final source = widget.projection.source;
    if (source == null || source.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: source));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制 artifact 源码')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projection = widget.projection;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(projection.title),
        actions: [
          if (_showSource && projection.source != null && projection.source!.trim().isNotEmpty)
            IconButton(
              tooltip: '复制源码',
              onPressed: _copySource,
              icon: const Icon(Icons.copy_all_outlined),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              projection.sourcePath,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('预览'),
                  icon: Icon(Icons.visibility_outlined),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('源码'),
                  icon: Icon(Icons.code_outlined),
                ),
              ],
              selected: <bool>{_showSource},
              onSelectionChanged: (selection) {
                setState(() {
                  _showSource = selection.first;
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
                child: _showSource
                  ? _ArtifactSourceView(source: projection.source)
                  : ArtifactPreviewSurface(
                      source: projection.source,
                      sourcePath: projection.sourcePath,
                      enableInternalScroll: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtifactSourceView extends StatelessWidget {
  const _ArtifactSourceView({
    required this.source,
  });

  final String? source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (source == null || source!.trim().isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text('当前没有可展示的 artifact 源码。'),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          source!,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'JetBrainsMono',
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
