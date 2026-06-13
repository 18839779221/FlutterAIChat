import 'package:flutter/widgets.dart';

import '../models/composer/composer_node.dart';
import '../models/speech/speech_input_state.dart';
import 'composer_document_controller.dart';
import 'composer_text_editing_controller.dart';
import 'voice_input_controller.dart';

class ComposerVoiceSyncController {
  final ComposerDocumentController composerController;
  final ComposerTextEditingController textController;
  final VoiceInputController voiceController;

  const ComposerVoiceSyncController({
    required this.composerController,
    required this.textController,
    required this.voiceController,
  });

  void syncFromVoiceState() {
    final state = voiceController.state;
    textController.updateSpeechDraftRange(
      start: state.draftRangeStart,
      end: state.draftRangeEnd,
    );

    if (state.isSessionActive) {
      _syncActiveDraft(state);
      return;
    }

    _syncIdleState(state);
  }

  void _syncActiveDraft(SpeechInputState state) {
    if (composerController.plainText.isEmpty && textController.text.isNotEmpty) {
      composerController.setPlainText(textController.text);
    }
    if (composerController.nodes.whereType<SpeechComposerNode>().isEmpty) {
      composerController.startSpeechNode(
        insertOffset: _resolveInsertOffset(textController),
      );
    }
    composerController.updateSpeechNode(
      finalizedText: '',
      interimText: state.draftText,
    );
  }

  void _syncIdleState(SpeechInputState state) {
    final hasActiveSpeechNode =
        composerController.nodes.whereType<SpeechComposerNode>().isNotEmpty;
    if (!hasActiveSpeechNode) {
      return;
    }
    if (state.committedText.isNotEmpty) {
      composerController.commitSpeechNode(state.committedText);
      return;
    }
    composerController.clearSpeechNode();
  }

  int _resolveInsertOffset(TextEditingController controller) {
    final selection = controller.selection;
    if (!selection.isValid) {
      return controller.text.length;
    }
    return selection.start.clamp(0, controller.text.length);
  }
}
