import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streaming message events expose message and content block lifecycle',
      () {
    const event = StreamingContentBlockDeltaEvent(
      messageId: 'resp_1',
      contentBlockId: 'resp_1:text',
      deltaType: StreamingContentDeltaType.text,
      value: 'hel',
    );

    expect(event.messageId, 'resp_1');
    expect(event.contentBlockId, 'resp_1:text');
    expect(event.deltaType, StreamingContentDeltaType.text);
    expect(event.value, 'hel');
  });

  test('tool-use block start preserves provider tool metadata', () {
    const event = StreamingContentBlockStartEvent(
      messageId: 'resp_2',
      contentBlockId: 'resp_2:tool:0',
      blockType: StreamingContentBlockType.toolUse,
      toolUseId: 'call_1',
      toolName: 'create_artifact',
      providerMetadata: {'response_id': 'resp_2'},
    );

    expect(event.messageId, 'resp_2');
    expect(event.contentBlockId, 'resp_2:tool:0');
    expect(event.blockType, StreamingContentBlockType.toolUse);
    expect(event.toolUseId, 'call_1');
    expect(event.toolName, 'create_artifact');
    expect(event.providerMetadata, containsPair('response_id', 'resp_2'));
  });
}
