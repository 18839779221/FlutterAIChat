enum ToolExecutionMode {
  conservative,
  balanced,
  aggressive,
}

enum ToolPolicyDecision {
  autoRun,
  requireConfirmation,
  blocked,
}

class ToolPolicy {
  final ToolExecutionMode defaultMode;
  final Set<String> autoRunWhitelist;
  final Set<String> blockedTools;

  const ToolPolicy({
    this.defaultMode = ToolExecutionMode.balanced,
    this.autoRunWhitelist = const {},
    this.blockedTools = const {},
  });

  ToolPolicy copyWith({
    ToolExecutionMode? defaultMode,
    Set<String>? autoRunWhitelist,
    Set<String>? blockedTools,
  }) {
    return ToolPolicy(
      defaultMode: defaultMode ?? this.defaultMode,
      autoRunWhitelist: autoRunWhitelist ?? this.autoRunWhitelist,
      blockedTools: blockedTools ?? this.blockedTools,
    );
  }
}
