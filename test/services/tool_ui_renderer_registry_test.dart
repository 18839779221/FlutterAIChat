import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/tool_ui_renderer_registry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolUiRendererRegistry', () {
    test('returns null for unregistered workflow renderer', () {
      const registry = ToolUiRendererRegistry(renderers: []);

      expect(registry.findWorkflowRenderer('Read'), isNull);
    });

    test('returns matching result renderer for Write', () {
      const registry = ToolUiRendererRegistry(
        renderers: [_FakeWriteRenderer()],
      );

      expect(registry.findResultRenderer('Write'), isA<_FakeWriteRenderer>());
    });
  });
}

class _FakeWriteRenderer implements ToolUiRenderer {
  const _FakeWriteRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return null;
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return null;
  }

  @override
  bool supportsResult(String toolName) => toolName == 'Write';

  @override
  bool supportsWorkflowStep(String toolName) => toolName == 'Write';
}
