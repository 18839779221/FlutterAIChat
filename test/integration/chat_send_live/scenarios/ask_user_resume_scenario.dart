import '../chat_send_live_scenario.dart';
import 'package:ai_chat/models/chat_turn.dart';

ScenarioCase buildAskUserResumeScenario() {
  return const ScenarioCase(
    id: 'ask_user_resume',
    title: 'Ask user resume continuation',
    userMessage: '你现在不能自行决定我的偏好，也不要直接在普通文本里提问。'
        '必须先调用 ask_user_question 工具，发起一个单选问题，'
        '问题 id 固定为 `storage_layer`，问题内容是“你希望我后续按哪种本地存储方案继续？”，'
        '并提供两个选项：`SQLite` 和 `Hive`。'
        '在我回答前，不要调用任何其他工具，也不要直接给结论。'
        '等我回答后，不要再次提问，不要调用其他工具，只用一句中文确认我的选择并结束当前 turn。',
    providerTargets: [
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.anthropicMessages,
      ),
    ],
  );
}
