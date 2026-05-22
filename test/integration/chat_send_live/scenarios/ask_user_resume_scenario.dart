import '../chat_send_live_scenario.dart';
import 'package:ai_chat/models/chat_turn.dart';

ScenarioCase buildAskUserResumeScenario() {
  return const ScenarioCase(
    id: 'ask_user_resume',
    title: 'Ask user resume continuation',
    userMessage: '我准备继续做本地存储这块，但还没决定后面按 SQLite 还是 Hive 往下走。'
        '如果这会影响你下一步怎么继续，请先问我一个单选问题让我选，'
        '我答完以后你再接着往下说，不用展开成长篇解释。',
    providerTargets: [
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.anthropicMessages,
      ),
    ],
  );
}
