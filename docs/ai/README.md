# OpenClaw Feature Workflow

This directory stores artifacts produced by the OpenClaw multi-agent pipeline.

## 1) Setup agent team

Run once (or rerun after config reset):

```bash
scripts/oc-team-setup.sh
```

What it does:

- Sets `agents.defaults.contextTokens` (default: `160000`)
- Keeps compaction mode at `safeguard`
- Ensures `lead`, `flutter-dev`, `qa` agents exist
- Binds Feishu channel routing to `lead` (can disable with `--no-feishu-bind`)
- Syncs workspace skill `skills/lead-feishu-flow` into `lead` agent workspace and managed skills (`~/.openclaw/skills`)
- Adds allowlist entries for `lead(git/bash/openclaw)` and `flutter-dev|qa(git/flutter/dart)` when binaries are in PATH

Optional env vars:

```bash
OC_LEAD_MODEL=codex-for-me/gpt-5.2 OC_DEV_MODEL=codex-for-me/gpt-5.3-codex OC_QA_MODEL=codex-for-me/gpt-5.2 OC_CONTEXT_TOKENS=160000 scripts/oc-team-setup.sh
```

Optional full setup (also creates `pm`, `architect`, `release`):

```bash
scripts/oc-team-setup.sh --full-team
```

Skip Feishu binding:

```bash
scripts/oc-team-setup.sh --no-feishu-bind
```

## 2) Run a feature pipeline

From repository root:

```bash
scripts/oc-feature.sh feat-chat-export --req "Users can export chat history to markdown"
```

Or use a requirement file:

```bash
scripts/oc-feature.sh feat-chat-export --req-file docs/requirements/chat-export.md
```

Enable architect stage when needed:

```bash
scripts/oc-feature.sh feat-chat-export --req "..." --with-architect
```

Pin a stable session when you explicitly want continuity across reruns:

```bash
scripts/oc-feature.sh feat-chat-export --req "..." --session-tag rerun1
```

Enable auto commit after release stage:

```bash
scripts/oc-feature.sh feat-chat-export --req "..." --auto-commit
```

Feishu-friendly wrapper (auto feature-id + auto-commit by default):

```bash
scripts/oc-feishu-flow.sh --req "把发送按钮文案改成发送消息"
```

Check status for a feature:

```bash
scripts/oc-feishu-flow.sh --status --id feat-20260313-010203
```

Useful reliability flags:

```bash
scripts/oc-feature.sh feat-chat-export --req "..." --require-gateway --max-attempts 3
```

Reuse base agents (disable run-scoped isolated agents):

```bash
scripts/oc-feature.sh feat-chat-export --req "..." --no-isolate-agents
```

## 3) Generated artifacts

Per feature ID, outputs are written to:

```text
docs/ai/<feature-id>/
```

Files:

- `00-input.md`
- `01-requirement.md`
- `02-design.md`
- `03-dev-notes.md`
- `04-test-report.md`
- `05-release.md`
- `06-commit-message.txt`
- `logs/lead-plan.json`
- `logs/dev.json`
- `logs/qa.json`
- `logs/lead-release.json`
- `logs/architect.json` (only when `--with-architect`)

## Notes

- Pipeline creates/switches branch `feature/<feature-id>`.
- Default flow is `lead -> flutter-dev -> qa -> lead`.
- By default each run uses run-scoped agents (`*-run-<session_tag>`) for stronger session isolation.
- Run-scoped agents are auto-removed at exit; pass `--keep-run-agents` to keep them for debugging.
- Keep one feature ID per requirement to avoid context mixing.
- If `flutter` is not in PATH, QA stage may fail. Ensure the gateway runtime can run Flutter commands.

## Feishu Commanding

Because Feishu is routed to `lead`, you can issue commands directly in Feishu, for example:

```text
请在 FlutterAIChat 仓库执行：
bash scripts/oc-feature.sh feat-rename-button --req \"把发送按钮文案改为发送消息\" --auto-commit
```

Or use natural command style (handled by `lead-feishu-flow` skill):

```text
新需求：把发送按钮文案改成发送消息
```

```text
重跑：feat-20260313-010203
```

```text
状态：feat-20260313-010203
```
