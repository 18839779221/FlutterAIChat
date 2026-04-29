import '../chat_send_live_scenario.dart';
import 'package:ai_chat/models/chat_turn.dart';

ScenarioCase buildMixedSuccessFailureScenario() {
  return const ScenarioCase(
    id: 'mixed_success_failure',
    title: 'Mixed success and failure continuation',
    userMessage: '请严格按下面流程执行，并在最后直接结束，不要扩展更多工具：\n'
        '1. 先调用一次 web_search，查询 `site:blog.google Gemini March 2026 updates`。\n'
        '2. 然后调用一次 Read，读取 `fixtures/does-not-exist.txt`。\n'
        '3. 如果 Read 失败，不要重试，不要改用其他文件工具，也不要继续调用其他工具。\n'
        '4. 基于已成功的 web_search 结果和这次 Read 失败事实，用中文简短说明“搜索成功、读取失败”，然后结束。',
    providerTargets: [
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.anthropicMessages,
      ),
    ],
  );
}
