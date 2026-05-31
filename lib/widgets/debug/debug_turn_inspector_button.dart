import 'package:flutter/material.dart';

class DebugTurnInspectorButton extends StatelessWidget {
  const DebugTurnInspectorButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
  });

  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('debug-turn-inspector-button'),
        customBorder: const CircleBorder(),
        onTap: onPressed,
        onLongPress: onLongPress,
        child: const SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Icon(Icons.bug_report_outlined, size: 16),
          ),
        ),
      ),
    );
  }
}
