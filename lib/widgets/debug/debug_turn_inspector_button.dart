import 'package:flutter/material.dart';

class DebugTurnInspectorButton extends StatelessWidget {
  const DebugTurnInspectorButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('debug-turn-inspector-button'),
      tooltip: 'Turn Inspector',
      onPressed: onPressed,
      icon: const Icon(Icons.bug_report_outlined, size: 16),
    );
  }
}
