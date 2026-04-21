# Feature TODO

这些是中长期待办，不一定是当前最高优先级，但希望后续实现时有统一落点。

## 候选功能

### 1. Context 管理策略升级与自动压缩
- 目标：提升长对话下的上下文质量与稳定性
- 方向：
  - 更精细的 context 选择策略
  - 在达到上下文上限时自动压缩历史内容
  - 区分高价值上下文、近期上下文、工具上下文
- 实现时额外关注：
  - 是否需要新的 trace 节点记录压缩前后上下文
  - 是否需要引入新的 summary/compaction payload 结构

### 2. 支持多模型同时配置
- 目标：让不同能力层级的模型承担不同任务，降低成本并提升主模型可用性
- 方向：
  - 主对话模型与轻量任务模型分离
  - 低端模型可承担会话总结、标题生成、轻量结构化等任务
  - 设置页支持多模型配置与用途分配
- 实现时额外关注：
  - 配置结构是否仍然保持通用厂商兼容
  - 任务路由是否需要 trace/log 覆盖
  - 自动化测试是否要覆盖多模型配置场景

### 3. Session 总结能力优化
- 目标：让总结更贴近真实对话段落，而不是只依赖当前简单触发条件
- 方向：
  - 支持“超过 N 分钟无对话，自动总结本次 session”
  - 支持更清晰的 session 边界定义
  - 支持总结结果回写为标题、阶段总结或摘要卡片
- 实现时额外关注：
  - 与现有 `ChatSummaryController` 的边界是否需要再拆分
  - 定时器、生命周期与前后台切换的稳定性
  - 是否要将总结触发原因加入 trace

### 4. 消息显示优化
- 要点
  - 发送新消息时，将当前消息列表清屏（历史消息被顶上去，避免占用用户可见区域，往下滑仍然能滑回去）
  - 消息持续流式输出时，用户能够滑动触发自由查看，不强制固定在底部
  - 进入App时，默认显示最新消息，而不是最老消息


## BUGFIX

### 1. Responses tool call 第二轮续接失败
- 现象：
  - 首轮 `ask_user_question` 等 tool call 能正常返回
  - 用户提交答案后，第二轮通过 `function_call_output + previous_response_id` 续接时失败
  - 当前会触发 `planner_request_failed`，并出现“抱歉，我暂时无法规划下一步动作，请直接重试。”
- 当前已知信息：
  - 我们发送的是 OpenAI Responses 官方格式的 continuation 请求
  - 请求里使用的是首轮返回的 `function_call.call_id`
  - 某些第三方 / 中转 Responses 实现会报错：
    - `No tool call found for function call output with call_id fc...`
  - 报错里识别的是 `fc...`，而不是首轮响应中的 `call_...`
- 已完成的辅助工作：
  - 已增加完整 request/response 落盘日志
  - 已增加 planner continuation 上下文与 provider 原始错误日志
  - 已确认首轮 planner 请求已收敛为单 `system` + 真实 `user`
- 后续排查方向：
  - 继续确认第三方 provider 是否错误使用了 `function_call.id` / `fc...`
  - 对照 OpenAI 官方 Responses 协议，判断是否需要做 provider 级兼容层
  - 在不污染主流程的前提下，评估是否需要区分“官方兼容”和“中转兼容”两套 continuation 映射策略

### 2. 同一 turn 内写工具成功后未收敛，导致重复写入循环
- 现象：
  - `Write` 工具在用户确认后执行成功
  - 当前 turn 没有在写入成功后结束，而是继续进入下一轮 planner
  - 后续 planner 在相同用户意图下再次规划 `Write`，形成同一 turn 内的重复写入
  - 日志中会出现同一个 `turnId` 下多次 `tool.done toolName=Write`，以及重复的 `已写入文件：xxx`
- 当前已知信息：
  - 这不是“同一 step 内重复 tool call”问题，而是跨 step 的重复 re-plan
  - 最新现场中，同一个 `turnId=5` 已出现多个 `Write` step，并在 `tool.done` 后继续 `planner.start`
  - 当前 transcript 会累计多条相同的 `已写入文件：个人信息.md`，进一步污染后续 planner 输入
- 后续排查方向：
  - 梳理 `TurnHarness` 在写工具成功后的收敛策略，确认哪些工具应在成功后优先结束 turn
  - 评估是否需要将 `Write` / `Edit` / 外部动作工具标记为“成功后优先收口”的 action 类工具
  - 避免 tool result 与 final answer 双重投影造成重复成功文本继续进入后续 planner 上下文
