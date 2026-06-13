import 'package:flutter/foundation.dart';

import '../models/composer/composer_node.dart';

class ComposerDocumentController extends ChangeNotifier {
  final List<ComposerNode> _nodes = <ComposerNode>[];
  String _plainText = '';
  int _speechNodeInsertOffset = 0;

  List<ComposerNode> get nodes => List<ComposerNode>.unmodifiable(_nodes);

  String get plainText => _plainText;

  void setPlainText(String text) {
    if (_plainText == text) {
      return;
    }
    _plainText = text;
    notifyListeners();
  }

  void insertCommand(String commandText) {
    if (_nodes.any(
      (node) => node is CommandComposerNode && node.commandText == commandText,
    )) {
      return;
    }
    _nodes.add(CommandComposerNode(commandText: commandText));
    notifyListeners();
  }

  void startSpeechNode({
    int? insertOffset,
  }) {
    _nodes.removeWhere((node) => node is SpeechComposerNode);
    _speechNodeInsertOffset = (insertOffset ?? _plainText.length).clamp(
      0,
      _plainText.length,
    );
    _nodes.add(const SpeechComposerNode());
    notifyListeners();
  }

  void updateSpeechNode({
    String? finalizedText,
    String? interimText,
  }) {
    final index = _nodes.indexWhere((node) => node is SpeechComposerNode);
    if (index < 0) {
      return;
    }
    final current = _nodes[index] as SpeechComposerNode;
    _nodes[index] = current.copyWith(
      finalizedText: finalizedText,
      interimText: interimText,
    );
    notifyListeners();
  }

  void commitSpeechNode(String finalText) {
    _nodes.removeWhere((node) => node is SpeechComposerNode);
    if (finalText.isNotEmpty) {
      final offset = _speechNodeInsertOffset.clamp(0, _plainText.length);
      _plainText = _plainText.replaceRange(offset, offset, finalText);
    }
    notifyListeners();
  }

  void clearSpeechNode() {
    final beforeLength = _nodes.length;
    _nodes.removeWhere((node) => node is SpeechComposerNode);
    final didRemove = _nodes.length != beforeLength;
    if (didRemove) {
      notifyListeners();
    }
  }

  void removeCommand(String commandText) {
    _nodes.removeWhere(
      (node) => node is CommandComposerNode && node.commandText == commandText,
    );
    notifyListeners();
  }

  String exportPlainText() {
    final commandText = _nodes
        .whereType<CommandComposerNode>()
        .map((node) => node.commandText)
        .join(' ');
    final text = _plainText.trim();
    if (commandText.isEmpty) {
      return text;
    }
    if (text.isEmpty) {
      return commandText;
    }
    return '$commandText $text';
  }
}
