import '../chat_send_live_scenario.dart';
import 'package:ai_chat/models/chat_turn.dart';

ScenarioCase buildMixedSuccessFailureScenario() {
  return const ScenarioCase(
    id: 'mixed_success_failure',
    title: 'Mixed success and failure continuation',
    userMessage: '帮我查一下 2026 年 3 月 Gemini 的更新，然后再看看 `fixtures/does-not-exist.txt` 这个文件。'
        '如果文件读不到，就直接告诉我搜索成功、读文件失败，不要反复重试，也别再绕去做别的操作。',
    providerTargets: [
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.anthropicMessages,
      ),
    ],
  );
}
