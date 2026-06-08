import '../chat_send_live_scenario.dart';
import 'package:ai_chat/models/chat_turn.dart';

ScenarioCase buildCreateArtifactTakeoverScenario() {
  return const ScenarioCase(
    id: 'create_artifact_takeover',
    title: 'Create artifact takeover',
    userMessage: '帮我用HTML可视化iOS架构',
    providerTargets: [
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.openaiResponses,
      ),
    ],
  );
}
