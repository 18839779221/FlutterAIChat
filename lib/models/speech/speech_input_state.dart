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

  /// Final transcript committed by the latest completed speech session.
  final String committedText;

  /// Start offset of the current inline speech draft range inside the composer.
  final int? draftRangeStart;

  /// End offset of the current inline speech draft range inside the composer.
  final int? draftRangeEnd;

  /// User-visible error message for the latest failed attempt, if any.
  final String? errorMessage;

  /// Whether the current runtime instance exposes a usable speech config.
  final bool isConfigured;

  /// Whether microphone permission is currently granted for the session.
  final bool hasPermission;

  const SpeechInputState({
    this.phase = SpeechInputPhase.idle,
    this.draftText = '',
    this.committedText = '',
    this.draftRangeStart,
    this.draftRangeEnd,
    this.errorMessage,
    this.isConfigured = false,
    this.hasPermission = false,
  });

  bool get isListening => phase == SpeechInputPhase.listening;
  bool get isSessionActive =>
      phase == SpeechInputPhase.requestingPermission ||
      phase == SpeechInputPhase.connecting ||
      phase == SpeechInputPhase.listening ||
      phase == SpeechInputPhase.finalizing;
  bool get hasDraftRange =>
      draftRangeStart != null &&
      draftRangeEnd != null &&
      draftRangeEnd! >= draftRangeStart!;

  SpeechInputState copyWith({
    SpeechInputPhase? phase,
    String? draftText,
    String? committedText,
    int? draftRangeStart,
    int? draftRangeEnd,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool clearDraftRange = false,
    bool? isConfigured,
    bool? hasPermission,
  }) {
    return SpeechInputState(
      phase: phase ?? this.phase,
      draftText: draftText ?? this.draftText,
      committedText: committedText ?? this.committedText,
      draftRangeStart:
          clearDraftRange ? null : draftRangeStart ?? this.draftRangeStart,
      draftRangeEnd: clearDraftRange ? null : draftRangeEnd ?? this.draftRangeEnd,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      isConfigured: isConfigured ?? this.isConfigured,
      hasPermission: hasPermission ?? this.hasPermission,
    );
  }
}
