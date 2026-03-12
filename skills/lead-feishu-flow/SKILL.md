---
name: lead-feishu-flow
description: Drive FlutterAIChat requirement delivery from Feishu natural-language messages. Use when the user asks to start, rerun, or check a feature pipeline and mentions phrases like 新需求, 需求开发, 跑流程, 重跑, 重试, 看进度, 状态, 提交代码. Translate the request into scripts/oc-feishu-flow.sh execution and return concise execution results.
---

# Lead Feishu Flow

## Repository Path

Use this repository root:

`/Users/skka/.openclaw/workspace/FlutterAIChat`

## Command Mapping

For start requests (for example "新需求：把发送按钮文案改成发送消息"):

1. Extract requirement text.
2. Run:

```bash
bash /Users/skka/.openclaw/workspace/FlutterAIChat/scripts/oc-feishu-flow.sh --req "<需求文本>"
```

For start requests with explicit feature id (for example "重跑 feat-login-timeout"):

```bash
bash /Users/skka/.openclaw/workspace/FlutterAIChat/scripts/oc-feishu-flow.sh --id "<feature-id>" --req "<需求文本>"
```

For status requests (for example "看下 feat-login-timeout 进度"):

```bash
bash /Users/skka/.openclaw/workspace/FlutterAIChat/scripts/oc-feishu-flow.sh --status --id "<feature-id>"
```

## Option Mapping

- If user asks for architecture review, add `--with-architect`.
- If user says not to commit, add `--no-auto-commit`.
- If user gives a specific requirement file path, use `--req-file`.
- If user gives session tag, pass `--session-tag`.

## Output Contract

After each run, return:

1. Feature id
2. Branch name
3. Last commit hash/message if available
4. QA/result summary (pass/fail/block reason)
5. Next action only when blocked

## Guardrails

- Ask one concise follow-up question only if requirement text is missing.
- Keep one requirement per run.
- Never run destructive git commands.
