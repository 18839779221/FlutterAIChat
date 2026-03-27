# Codex Reasoning 排查结论

日期：2026-03-27

## 结论摘要

当前 Codex 这套 `baseUrl + model` 方案下，“深度思考”功能并不是完全没生效。

已经确认的情况是：

1. 前端可以成功把 `reasoning.effort=medium` 发到 `/responses`
2. 服务端也确实进入了 reasoning 模式
3. 但返回给前端的 reasoning 内容只有 `encrypted_content`，没有可展示的 `summary_text`
4. 因此前端最终只能显示答案，不能显示“思考过程”

换句话说，当前问题的核心不是“前端没有请求 reasoning”，而是“当前链路没有返回可读 reasoning 内容”。

## 已确认事实

### 1. 请求可以带上 reasoning

在浏览器自动化测试中，已抓到真实请求体包含：

```json
"reasoning":{"effort":"medium"}
```

这说明页面上的“深度思考”开关在部分请求中是能真正传递到后端的。

### 2. 服务端确实执行了 reasoning

在原始 SSE 返回流中可以看到：

```json
"reasoning":{"effort":"medium","summary":null}
```

同时在 `response.completed` 的 `usage` 中可以看到：

```json
"output_tokens_details":{"reasoning_tokens":12}
```

这说明本次请求不是“完全没有 reasoning”，而是模型执行了 reasoning，但没有返回可读摘要。

### 3. 返回的 reasoning item 不可直接展示

当前抓到的 reasoning item 结构是：

```json
{
  "type":"reasoning",
  "encrypted_content":"...",
  "summary":[]
}
```

已确认：

1. 没有 `summary_text`
2. 没有 `response.reasoning.delta`
3. 没有 `response.reasoning_summary_text.delta`

因此前端没有任何可以直接渲染到 UI 的 reasoning 文本。

### 4. 当前前端解析逻辑不是主因

项目内已经补充了对 OpenAI Responses reasoning item 的解析支持，位置：

- [api_stream_parser.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/models/llm/api_stream_parser.dart)
- [api_stream_parser_test.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/test/models/llm/api_stream_parser_test.dart)

该解析器会：

1. 解析 `response.reasoning.delta`
2. 解析 `response.reasoning_summary_text.delta`
3. 解析 `response.output_item.added/done` 中 `item.type == "reasoning"` 且 `summary` 内有 `summary_text` 的情况

所以对于“只有 `encrypted_content`、`summary: []`”的返回，当前无法显示 reasoning 是符合现有实现和返回事实的。

## 目前最稳的判断

当前 Codex 方案下，“没有 reasoning 可显示”的直接原因是：

1. 网关/模型链路返回了加密 reasoning
2. 但没有返回可读 summary
3. 前端没有官方可用的本地解密方案

因此 UI 无法展示“思考过程”。

## 关于本地解密的判断

基于 OpenAI 官方文档，目前没有查到任何“客户端本地解密 `encrypted_content`”的公开方案、密钥机制或 SDK 用法。

目前更合理的判断是：

1. `encrypted_content` 不是给前端本地解密展示用的
2. 它更像是给服务端或后续请求回传使用的加密 reasoning 载荷
3. 如果网关只返回 `encrypted_content` 而不返回 `summary_text`，前端就没有可展示文本

这部分判断基于官方文档与当前抓包结果的对照，不是代码层猜测。

## 排查过程中需要注意的噪音

浏览器自动化排查里曾出现过“有时带 reasoning、有时不带 reasoning”的现象。

后续复盘后确认，这里面掺杂了一个实验噪音：

1. `useReasoning` 是前端内存状态
2. 连续自动化点击同一个开关时，可能把按钮从“开”切到“关”
3. 如果没有先归一状态，就会误判为“某种点击方式失效”

因此后续判断是否生效时，应优先以“请求体里是否带 `reasoning`”为准，而不是只看按钮文案。

## 当前证据摘要

本次排查中已经确认：

1. 请求带了 `reasoning.effort=medium`
2. 返回包含 `type:"reasoning"`
3. reasoning item 只有 `encrypted_content`
4. `summary` 为空数组
5. 最终答案仍正常返回

浏览器自动化截图和原始抓包文件曾保存在 `output/playwright/reasoning/` 下，用于排查阶段验证按钮状态与原始 SSE。当前结论文档已经吸收了必要证据，因此这些临时实验产物可以清理，不再作为长期项目文件保留。

## 下一步建议

后续排查建议按下面顺序继续：

1. 确认当前网关是否支持返回 `summary_text`
2. 确认是否需要额外请求参数才能返回可读 reasoning summary
3. 如果当前链路只能返回 `encrypted_content`，则在 UI 上明确提示“已启用深度思考，但当前服务未返回可展示推理内容”
