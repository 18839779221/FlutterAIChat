import 'package:ai_chat/widgets/chat_empty_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default empty suggestions expose ask-user-question manual test cases',
      () {
    expect(defaultChatEmptySuggestions, hasLength(4));
    expect(
      defaultChatEmptySuggestions.map((item) => item.label),
      containsAll(<String>[
        '单题问答',
        'Other 自定义',
        '多题澄清',
        '多选优先级',
      ]),
    );
    expect(
      defaultChatEmptySuggestions
          .firstWhere((item) => item.label == '单题问答')
          .prompt,
      contains('请先向我提一个关键澄清问题'),
    );
    expect(
      defaultChatEmptySuggestions
          .firstWhere((item) => item.label == 'Other 自定义')
          .prompt,
      contains('请先问我该选什么存储方案'),
    );
    expect(
      defaultChatEmptySuggestions
          .firstWhere((item) => item.label == '多题澄清')
          .prompt,
      contains('请把这些关键问题一次性问我'),
    );
    expect(
      defaultChatEmptySuggestions
          .firstWhere((item) => item.label == '多选优先级')
          .prompt,
      contains('允许多选'),
    );
  });
}
