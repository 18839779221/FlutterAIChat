---
name: create-artifact-render-analysis
description: Use when diagnosing FlutterAIChat create_artifact inline preview issues such as remounts, white screen during loading, height jumps, or long streaming where UI only renders at the end, especially after reproducing on Android and needing log-backed flow analysis.
---

# Create Artifact Render Analysis

## Overview

Use this skill to run the repository-standard create_artifact render diagnosis flow.

The source of truth is the app-private `app.log` plus the repo analyzers at:

- `tool/analyze_create_artifact_render_log.dart`
- `tool/analyze_streaming_trace_log.dart`

Do not infer render incidents from scattered raw lines by hand when these analyzers can reconstruct the flow and timeline.

## Standard Flow

1. If you are preparing a fresh repro on Android, clear the app log first:
   - `bash scripts/android_capture_app_log.sh clear <device_id>`
2. Reproduce one `create_artifact` run on device.
3. Analyze the latest log with the repo wrapper:
   - `bash scripts/analyze_create_artifact_render.sh latest <device_id>`
   - for a one-shot readable diagnosis report, prefer:
     `bash scripts/analyze_create_artifact_render.sh latest <device_id> --report`
   - for the paired artifact+timeline diagnosis, prefer:
     `bash scripts/analyze_create_artifact_incident.sh latest <device_id>`
4. If the log was already exported, analyze the file directly:
   - `bash scripts/analyze_create_artifact_render.sh file build/artifact-debug/create_artifact_latest.log`

## What The Analyzer Already Does

- groups one logical render incident by `flowId`
- falls back to `turnId + artifactId + providerCallId` when older logs do not contain `flowId`
- treats multiple render attempts inside one flow as remount evidence
- distinguishes `unique sessionId` count from total render-attempt count
- flags reused `sessionId` across multiple attempts as legacy observability evidence
- picks one primary render attempt with the strongest render signal for quick reading
- emits flow-level `summarySignals` / `summaryLabel` so automation can identify the main incident class before drilling into attempts
- emits attempt-level `derivedSignals` such as truncation release, truncation-release drop, and drop-then-recover patterns
- surfaces anomaly codes like:
  - `artifact_height_drop_over_30px`
  - `artifact_first_render_in_final_second`

## How To Read Results

- `Selected flow` is the main incident the analyzer chose. By default it uses the latest flow in the log.
- `Artifact incident report` is the best default for quick triage. It already folds flow summary, main findings, and primary-attempt evidence into one output.
- `Streaming timeline incident report` is the best default for “streamed a long time but UI only became visible at the end”. It folds total elapsed time, first visible timing, tail window, and final-answer first-chunk / streaming metrics into one output.
- `Flow summary` is the first thing to read. It compresses one flow into a stable incident label like `remount + final_takeover_drop`.
- `Attempts` tells you how many render attempts happened inside that one flow.
- `Remount evidence` is the fast signal for whether this was one clean mount or several restarts/remounts.
- `Primary attempt` is the attempt to inspect first when judging whether UI rendered progressively or only at the end.
- `signals` under the primary attempt are the structured per-attempt clues to prioritize before reading raw log lines.
- `firstSuccessfulRenderAtMs` near the tail of a long `durationMs` is the signature for “streamed for a long time, then rendered all at once at the end”.
- `effectiveFirstVisibleAtMs` near the tail of a long `totalElapsedMs` is the timeline signature for “tool-call/final-answer streamed, but UI only appeared at the end”.

## Useful Variants

- Inspect a specific flow:
  - `bash scripts/analyze_create_artifact_render.sh file build/artifact-debug/create_artifact_latest.log --flow-id <flowId>`
- Inspect a specific timeline trace:
  - `bash scripts/analyze_streaming_trace.sh file build/artifact-debug/latest.log --trace-id <traceId>`
- Emit JSON instead of human summary:
  - `bash scripts/analyze_create_artifact_render.sh file build/artifact-debug/create_artifact_latest.log --json`
- Emit timeline JSON instead of human summary:
  - `bash scripts/analyze_streaming_trace.sh file build/artifact-debug/latest.log --json`
- Emit a ready-to-read incident report:
  - `bash scripts/analyze_create_artifact_render.sh file build/artifact-debug/create_artifact_latest.log --report`
- Emit a paired artifact+timeline incident report:
  - `bash scripts/analyze_create_artifact_incident.sh file build/artifact-debug/latest.log`

## Guardrails

- Prefer `flowId` analysis over counting raw `session_started` lines manually.
- Prefer the repo analyzers over hand-scanning `ChatTrace` / `StreamingTraceRecorder` lines.
- Treat same-flow multiple `sessionId` values as remount evidence, not separate user incidents.
- If the log predates `flowId`, call out that the analyzer used derived fallback grouping.
- For white-screen or “finally all rendered at once” cases, prioritize `Flow summary`, `durationMs`, `firstSuccessfulRenderAtMs`, `tailWindowMs`, `domCommitCount`, and `heightAppliedCount`.
- For “整段回复卡住，最后一股脑出来” cases, prioritize:
  1. timeline `Summary signals`
  2. `totalElapsedMs`
  3. `firstVisibleAtMs` / `effectiveFirstVisibleAtMs`
  4. `tailWindowMs`
  5. final-answer segment `firstChunkDelayMs` / `streamingDurationMs`
- For height-jump cases, read in this order:
  1. `Flow summary`
  2. primary-attempt `signals`
  3. primary-attempt `heightPattern / max / final / drop`
  4. same-flow other attempts as remount or repeat evidence
