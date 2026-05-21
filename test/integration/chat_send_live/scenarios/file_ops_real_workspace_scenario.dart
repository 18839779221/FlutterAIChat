import '../chat_send_live_scenario.dart';
import 'package:ai_chat/models/chat_turn.dart';

ScenarioCase buildRealWorkspaceFileOpsScenario() {
  return const ScenarioCase(
    id: 'file_ops_real_workspace',
    title: 'Real workspace file ops',
    userMessage: '帮我看看这个工作区里的 docs 目录。'
        '我想先知道里面有哪些内容，再看看 spec.md，顺手搜一下还有没有 TODO。'
        '最后请整理一段中文总结写到 artifacts/summary.md 里；如果要真正写文件，先按正常流程等我确认。',
    providerTargets: [
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.anthropicMessages,
      ),
    ],
  );
}
