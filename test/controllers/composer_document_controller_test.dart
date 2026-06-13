import 'package:ai_chat/controllers/composer_document_controller.dart';
import 'package:ai_chat/models/composer/composer_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerDocumentController', () {
    test('inserts command node and exports plain text with trailing composer text',
        () {
      final controller = ComposerDocumentController();

      controller.insertCommand('/compact');
      controller.setPlainText('整理今天的上下文');

      expect(
        controller.nodes.whereType<CommandComposerNode>().single.commandText,
        '/compact',
      );
      expect(controller.plainText, '整理今天的上下文');
      expect(
        controller.exportPlainText(),
        '/compact 整理今天的上下文',
      );
    });

    test('removes command node as a single block', () {
      final controller = ComposerDocumentController();

      controller.insertCommand('/compact');
      controller.setPlainText('整理今天的上下文');
      controller.removeCommand('/compact');

      expect(controller.nodes.whereType<CommandComposerNode>(), isEmpty);
      expect(controller.exportPlainText(), '整理今天的上下文');
    });

    test('tracks active speech node lifecycle and commits it into plain text',
        () {
      final controller = ComposerDocumentController();

      controller.setPlainText('帮我安排一下今天');
      controller.startSpeechNode(insertOffset: 6);
      controller.updateSpeechNode(interimText: '明天下午');
      controller.updateSpeechNode(
        finalizedText: '明天下午三点',
        interimText: '开会',
      );

      final speechNode = controller.nodes.whereType<SpeechComposerNode>().single;
      expect(speechNode.finalizedText, '明天下午三点');
      expect(speechNode.interimText, '开会');

      controller.commitSpeechNode('明天下午三点开会');

      expect(controller.nodes.whereType<SpeechComposerNode>(), isEmpty);
      expect(controller.plainText, '帮我安排一下明天下午三点开会今天');
      expect(
        controller.exportPlainText(),
        '帮我安排一下明天下午三点开会今天',
      );
    });

    test('keeps persisted plain text unchanged while active speech node updates',
        () {
      final controller = ComposerDocumentController();

      controller.setPlainText('帮我安排一下今天');
      controller.startSpeechNode(insertOffset: 6);
      controller.updateSpeechNode(interimText: '明天下午');

      expect(controller.plainText, '帮我安排一下今天');
      expect(controller.exportPlainText(), '帮我安排一下今天');
      expect(controller.nodes.whereType<SpeechComposerNode>(), hasLength(1));
    });
  });
}
