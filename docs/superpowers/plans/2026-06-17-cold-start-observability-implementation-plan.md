# Cold Start Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add measurable cold-start timing anchors to the existing `app.log` flow so startup improvements can be verified without relying on subjective feel.

**Architecture:** Introduce a small bootstrap startup probe that starts timing before `runApp()`, buffers early startup events until `Logger.initialize()` is ready, then flushes them into `app.log`. Wire the probe through `AppBootstrapScope` and `ChatInput` so the real startup path logs first-frame, composer-editable, and ready milestones exactly once.

**Tech Stack:** Flutter, Riverpod, existing `Logger`, Flutter widget/unit tests

---

### Task 1: Add a bootstrap startup probe with tests

**Files:**
- Create: `lib/bootstrap/bootstrap_startup_probe.dart`
- Create: `test/bootstrap/bootstrap_startup_probe_test.dart`

- [ ] **Step 1: Write failing probe tests**
- [ ] **Step 2: Run the probe tests and verify they fail**
- [ ] **Step 3: Implement the minimal buffering and once-only probe**
- [ ] **Step 4: Re-run the probe tests**

### Task 2: Wire probe into bootstrap scope and chat input

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/bootstrap/app_bootstrap_scope.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/widgets/chat_input.dart`
- Modify: `test/bootstrap/app_bootstrap_scope_test.dart`
- Modify: `test/widgets/chat_input_test.dart`

- [ ] **Step 1: Extend widget tests to cover startup anchor emission**
- [ ] **Step 2: Run targeted widget tests and verify they fail**
- [ ] **Step 3: Wire the probe through startup lifecycle and composer lifecycle**
- [ ] **Step 4: Re-run targeted widget tests**

### Task 3: Document and verify

**Files:**
- Modify: `docs/architecture/logging.md`

- [ ] **Step 1: Document the new startup anchor logs**
- [ ] **Step 2: Run targeted tests plus targeted analyze**
- [ ] **Step 3: Summarize how to read the new timings from `app.log`**
