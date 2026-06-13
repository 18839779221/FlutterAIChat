abstract class ComposerNode {
  const ComposerNode();
}

class TextComposerNode extends ComposerNode {
  const TextComposerNode(this.text);

  final String text;
}

class CommandComposerNode extends ComposerNode {
  const CommandComposerNode({
    required this.commandText,
  });

  final String commandText;
}

class SpeechComposerNode extends ComposerNode {
  const SpeechComposerNode({
    this.finalizedText = '',
    this.interimText = '',
  });

  final String finalizedText;
  final String interimText;

  SpeechComposerNode copyWith({
    String? finalizedText,
    String? interimText,
  }) {
    return SpeechComposerNode(
      finalizedText: finalizedText ?? this.finalizedText,
      interimText: interimText ?? this.interimText,
    );
  }

  String get visibleText => '$finalizedText$interimText';
}
