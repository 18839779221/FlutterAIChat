import 'package:flutter/material.dart';

/// Streaming cursor that blinks with a breathing rhythm.
///
/// Used during AI streaming responses to indicate "thinking" state.
/// Based on Claude's typing cursor pattern.
class StreamingCursor extends StatefulWidget {
  final bool isVisible;
  final Color color;
  final double width;
  final double height;

  const StreamingCursor({
    super.key,
    required this.isVisible,
    required this.color,
    this.width = 2,
    this.height = 18,
  });

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800), // Breathing cycle
      vsync: this,
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine, // Breathing curve - smooth loop
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _opacityAnimation,
      child: Container(
        width: widget.width,
        height: widget.height,
        margin: const EdgeInsets.only(left: 1),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
