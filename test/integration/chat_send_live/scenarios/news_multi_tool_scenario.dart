import '../chat_send_live_scenario.dart';
import 'package:ai_chat/models/chat_turn.dart';

ScenarioCase buildNewsMultiToolScenario() {
  return const ScenarioCase(
    id: 'news_multi_tool',
    title: 'News multi-tool continuation',
    userMessage:
        '帮我快速整理一下 Google AI 最近的两条相关新闻或动态，最好一条偏官方，一条偏媒体观察。'
        '给我一个中文简洁总结，并把来源带上；如果已经够用了，就别一路继续展开抓更多页面。',
    providerTargets: [
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.anthropicMessages,
      ),
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.openaiResponses,
      ),
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.openaiChatCompletions,
      ),
    ],
  );
}
