import '../chat_send_live_scenario.dart';
import 'package:ai_chat/models/chat_turn.dart';

ScenarioCase buildNewsMultiToolScenario() {
  return const ScenarioCase(
    id: 'news_multi_tool',
    title: 'News multi-tool continuation',
    userMessage:
        '请严格按下面流程执行，并在完成后立刻结束，不要自行扩展更多搜索或重试：\n'
        '1. 先调用一次 web_search，查询 `site:blog.google Google AI updates March 2026`。\n'
        '2. 再调用一次 web_search，查询 `site:androidcentral.com Google in 2026 what we expect want to see`。\n'
        '3. 基于这两次 web_search 的结果直接给我一个中文简洁总结，并附 Sources。\n'
        '4. 完成第二次 web_search 后立刻总结，不要继续调用 fetch_webpage，也不要继续换其他查询或重试。\n'
        '5. 不要跳过第二次工具调用，也不要只做一次工具调用。',
    providerTargets: [
      ProviderMatrixTarget(
        providerId: 'deepseek-anthropic',
        style: ChatTurnProviderStyle.anthropicMessages,
      ),
      ProviderMatrixTarget(
        providerId: 'beehears-responses',
        style: ChatTurnProviderStyle.openaiResponses,
      ),
      ProviderMatrixTarget(
        providerId: 'minimax-openai-chat-completions',
        style: ChatTurnProviderStyle.openaiChatCompletions,
      ),
    ],
  );
}
