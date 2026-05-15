enum SpeechInputPhase {
  idle,
  requestingPermission,
  connecting,
  listening,
  finalizing,
  error,
}

class SpeechInputState {
  /// Current lifecycle phase for one voice input attempt.
  final SpeechInputPhase phase;

  /// Realtime speech draft text shown before the final transcript is committed.
  final String draftText;

  /// User-visible error message for the latest failed attempt, if any.
  final String? errorMessage;

  /// Whether the current runtime instance exposes a usable speech config.
  final bool isConfigured;

  /// Whether microphone permission is currently granted for the session.
  final bool hasPermission;

  const SpeechInputState({
    this.phase = SpeechInputPhase.idle,
    this.draftText = '',
    this.errorMessage,
    this.isConfigured = false,
    this.hasPermission = false,
  });

  bool get isListening => phase == SpeechInputPhase.listening;

  SpeechInputState copyWith({
    SpeechInputPhase? phase,
    String? draftText,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isConfigured,
    bool? hasPermission,
  }) {
    return SpeechInputState(
      phase: phase ?? this.phase,
      draftText: draftText ?? this.draftText,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      isConfigured: isConfigured ?? this.isConfigured,
      hasPermission: hasPermission ?? this.hasPermission,
    );
  }
}
