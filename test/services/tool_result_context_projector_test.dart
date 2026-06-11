import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/tool_result_context_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate_image projection excludes inline base64 image data', () {
    const projector = ToolResultContextProjector();
    const result = ToolResult(
      toolName: 'generate_image',
      status: ToolExecutionStatus.success,
      summary: '已生成图片',
      data: {
        'prompt': 'A calendar cover',
        'model': 'gpt-image-2',
        'generatedImages': [
          {
            'localId': 'generated-1',
            'fileName': 'generated.png',
            'mimeType': 'image/png',
            'dataUrl': 'data:image/png;base64,AAAA',
          },
        ],
      },
    );

    final projected = projector.projectToContextText(result);

    expect(projected, contains('generate_image generated 1 image'));
    expect(projected, contains('model: gpt-image-2'));
    expect(projected, contains('prompt: A calendar cover'));
    expect(projected, isNot(contains('data:image')));
    expect(projected, isNot(contains('base64')));
    expect(projected, isNot(contains('AAAA')));
  });
}
