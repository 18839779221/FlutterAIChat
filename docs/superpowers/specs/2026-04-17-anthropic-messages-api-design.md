# Anthropic Messages API Compatibility Design

## Background

The current runtime-configurable HTTP LLM path supports two wire protocols:

- OpenAI-style `responses`
- OpenAI-style `chat/completions`

Protocol detection, request construction, stream parsing, and provider-native tool-loop parsing are all shaped around these two formats. We need to add compatibility for Anthropic's official `v1/messages` API format so the app can work with direct Anthropic endpoints and third-party relays that preserve the same wire format.

This design keeps the existing runtime entry point and internal chat/tool abstractions intact while introducing Anthropic as a third protocol family.

## Goals

- Support Anthropic Messages API through the existing runtime-configured LLM path
- Preserve the current `BaseLLM` surface and controller/provider architecture
- Keep protocol selection automatic from the configured base URL
- Support both direct assistant replies and provider-native tool use
- Stream Anthropic text output into the existing incremental chat UI
- Map Anthropic `thinking`-style output into the existing reasoning channel when present

## Non-Goals

- Full support for every Anthropic-specific capability in the first version
- Prompt caching, container management, or other advanced provider-specific features
- Introducing a second top-level runtime LLM type selection flow
- Refactoring the whole provider loop architecture while adding this support

## Recommended Approach

Add Anthropic as a third `ApiStyle` within the existing configurable HTTP LLM stack.

This keeps the current product model unchanged:

- user provides API key, base URL, and model
- runtime resolver infers the provider wire format from the endpoint
- the app reuses one internal message model and one agent/tool orchestration model

Compared with embedding Anthropic logic directly into existing OpenAI branches, a third protocol variant keeps the design legible. Compared with introducing a separate `AnthropicHttpLLM`, this avoids forcing a new configuration mode that does not match the current app direction.

## Architecture Changes

### 1. Protocol Resolution

`ApiProtocolResolver` will gain a new `ApiStyle.anthropicMessages`.

Resolution rules:

- path ending with `/v1/messages` resolves to `anthropicMessages`
- path ending with `/chat/completions` resolves to `chatCompletions`
- all other paths continue to default to `responses`

Request URI construction rules:

- if style is `anthropicMessages` and the configured URL already ends with `/v1/messages`, use it as-is
- otherwise append `/v1/messages`

This keeps current behavior unchanged for OpenAI-compatible endpoints while allowing Anthropic-compatible endpoints to be selected by URL.

### 2. Request Construction

`ConfigurableHttpLLM` will add a third request family for Anthropic.

Headers:

- `content-type: application/json`
- `x-api-key: <apiKey>`
- `anthropic-version: 2023-06-01`

Optional pass-through headers may be read from `LLMConfig.additionalConfig` for proxy-specific needs later, but the first version should only rely on the standard Anthropic requirements plus the existing runtime fields.

Payload shape:

- `model`
- `system` when a system prompt is present
- `messages`
- `stream`
- `max_tokens`
- `tools` when planner/native tool calling is active
- `tool_choice` when needed for structured planner requests

Internal-to-Anthropic message mapping:

- system prompt is emitted through the top-level `system` field
- user and assistant messages are mapped into Anthropic `messages`
- tool results are emitted as `user` messages with `tool_result` content blocks
- assistant tool calls are interpreted from `tool_use` blocks in the provider response

### 3. Stream Parsing

`ApiStreamParser` will gain Anthropic SSE parsing.

First-version stream handling:

- emit assistant text deltas as existing internal `content` chunks
- emit `thinking` and `redacted_thinking` text as existing internal `reasoning` chunks when exposed by the provider stream
- ignore unsupported non-text block events safely

The parser should stay tolerant:

- ignore unknown event types
- continue parsing partial streams where possible
- avoid failing the whole response because an optional provider block is not recognized

### 4. Tool Loop Parsing

A new Anthropic-specific tool-loop adapter will parse provider-native decisions into the existing internal model:

- `tool_use` blocks map to `ModelToolCall`
- assistant text blocks aggregate into the final assistant message
- provider continuation state stores only the minimum required Anthropic state for follow-up calls

This mirrors the existing split between request orchestration and provider-specific decision parsing used for OpenAI-compatible protocols.

### 5. Planner and Turn Decision Support

Anthropic support needs to work in three existing non-chat request modes:

- `planNextAction`
- `planNextToolChoice`
- `planTurnDecision`

The implementation should preserve the existing behavior contract:

- if the provider emits a tool call, return a non-terminal tool decision
- if the provider emits plain assistant content, return a terminal assistant decision
- if the provider returns an unsupported shape, fail soft and allow current fallback behavior where applicable

## Data Flow

### Normal chat flow

1. Runtime settings load base URL, API key, and model
2. Protocol resolver identifies Anthropic Messages style
3. `ConfigurableHttpLLM` builds Anthropic headers and payload
4. Response stream is parsed into internal `content` and `reasoning` chunks
5. Existing chat UI and persistence continue unchanged

### Tool use flow

1. Planner request includes Anthropic `tools`
2. Provider returns `tool_use` blocks
3. Anthropic adapter converts them into `ModelToolCall`
4. Existing orchestrator executes tools
5. Tool outputs are converted into Anthropic `tool_result` blocks for continuation
6. Provider emits final assistant text or additional tool requests

## Error Handling

Anthropic support should follow the current configurable HTTP behavior:

- non-200 responses surface provider status code and response body preview
- malformed stream events are logged and skipped where possible
- unsupported planner responses fall back without crashing the turn
- invalid runtime config remains validated before request execution

Additional guardrails:

- if a configured Anthropic endpoint is missing `model`, fail before request
- if a tool result cannot be matched to a provider tool call id, log and omit continuation rather than sending malformed payload

## Testing Strategy

Add targeted tests rather than broad refactors.

Required tests:

- protocol resolver detects `/v1/messages`
- request URI construction appends `/v1/messages` correctly
- Anthropic request headers include `x-api-key` and `anthropic-version`
- chat payload maps system prompt and messages correctly
- stream parser emits text deltas into internal `content`
- stream parser maps thinking events into internal `reasoning`
- planner/tool-loop parsing extracts `tool_use`
- planner/tool-loop parsing falls back to direct assistant text
- tool result continuation payload uses Anthropic `tool_result`

## Rollout Notes

This should ship as a compatibility extension, not a behavior change for existing OpenAI-compatible users.

Safety conditions:

- existing `responses` and `chat/completions` tests must continue to pass
- Anthropic path should be activated only by endpoint shape
- no UI changes are required for the first version because the app already has a reasoning channel and tool-use rendering path

## Open Decisions Resolved

- Anthropic `thinking` output will be mapped into the existing reasoning channel
- direct Anthropic endpoints and third-party relays using the same official Messages API format are both in scope

## Implementation Outline

1. Extend protocol detection and request URI building
2. Add Anthropic request headers and payload builders
3. Add Anthropic SSE stream parsing
4. Add Anthropic tool-loop adapter
5. Wire planner and turn-decision branches through the new protocol
6. Add focused tests for protocol, streaming, and tool use behavior
