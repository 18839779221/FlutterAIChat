import '../chat_send_live_scenario.dart';
import 'package:ai_chat/models/chat_turn.dart';

ScenarioCase buildRealWorkspaceFileOpsScenario() {
  return const ScenarioCase(
    id: 'file_ops_real_workspace',
    title: 'Real workspace file ops',
    userMessage: '请严格按下面流程使用文件工具，并在完成后结束：\n'
        '1. 先调用一次 LS 查看 `docs` 目录。\n'
        '2. 再调用一次 Read 读取 `docs/spec.md`。\n'
        '3. 再调用一次 Grep，在 `docs` 目录内搜索 `TODO`。\n'
        '4. 最后调用一次 Write，把一段中文总结写入 `artifacts/summary.md`。\n'
        '5. Write 提案出来后先停下等待确认，不要绕过确认。\n'
        '6. 确认后不要再调用其他工具，只用一句中文说明已经写入总结并结束。',
    providerTargets: [
      ProviderMatrixTarget(
        style: ChatTurnProviderStyle.anthropicMessages,
      ),
    ],
  );
}
