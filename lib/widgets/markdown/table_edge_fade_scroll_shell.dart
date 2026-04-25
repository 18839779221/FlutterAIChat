import 'package:flutter/material.dart';

/// Horizontal table shell with subtle edge fades when more content exists.
class TableEdgeFadeScrollShell extends StatefulWidget {
  final Widget child;

  const TableEdgeFadeScrollShell({
    super.key,
    required this.child,
  });

  @override
  State<TableEdgeFadeScrollShell> createState() =>
      _TableEdgeFadeScrollShellState();
}

class _TableEdgeFadeScrollShellState extends State<TableEdgeFadeScrollShell> {
  final ScrollController _scrollController = ScrollController();
  bool _showLeftFade = false;
  bool _showRightFade = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    _updateFades();
  }

  void _updateFades() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final showLeft = position.pixels > 1;
    final showRight = position.pixels < position.maxScrollExtent - 1;
    if (showLeft == _showLeftFade && showRight == _showRightFade) {
      return;
    }
    setState(() {
      _showLeftFade = showLeft;
      _showRightFade = showRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surface;

    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
        if (_showLeftFade)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: _TableEdgeFade(
                key: const ValueKey('table-edge-fade-left'),
                begin: background,
                end: background.withValues(alpha: 0),
              ),
            ),
          ),
        if (_showRightFade)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: _TableEdgeFade(
                key: const ValueKey('table-edge-fade-right'),
                begin: background,
                end: background.withValues(alpha: 0),
                mirrored: true,
              ),
            ),
          ),
      ],
    );
  }
}

class _TableEdgeFade extends StatelessWidget {
  final Color begin;
  final Color end;
  final bool mirrored;

  const _TableEdgeFade({
    super.key,
    required this.begin,
    required this.end,
    this.mirrored = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: mirrored ? Alignment.centerRight : Alignment.centerLeft,
            end: mirrored ? Alignment.centerLeft : Alignment.centerRight,
            colors: [begin, begin.withValues(alpha: 0.78), end],
            stops: const [0, 0.48, 1],
          ),
        ),
      ),
    );
  }
}
