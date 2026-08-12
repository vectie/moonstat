# MoonClaw harness metrics at the MoonGate boundary

MoonClaw records per-planner-round prompt, tool, and cache observations under
the `moonclaw.planner.metrics.v1` contract. These observations explain harness
efficiency without changing model requests, routing, cache policy, or tool
execution.

MoonGate remains the source of truth for provider traffic and aggregate usage.
MoonClaw remains the source of truth for the shape of an agent round. Join the
two with the existing request/session correlation evidence; do not copy raw
session IDs, prompts, paths, or tool arguments into Prometheus labels.

## Metric mapping

| MoonClaw planner field | Meaning | MoonGate counterpart |
| --- | --- | --- |
| `prompt_tokens` | Provider-reported input tokens, including cache reads | `moongate_input_tokens_total` and usage-log input tokens |
| `cache_read_tokens` | Provider-reported cached input tokens | `moongate_cache_read_tokens_total` and usage-log cache tokens |
| `fresh_input_tokens` | `max(prompt_tokens - cache_read_tokens, 0)` | derive during joined analysis; do not add a high-cardinality series |
| `cache_read_ratio_ppm` | cached share of input in parts per million | derive for a task or benchmark cohort |
| `completion_tokens` | Provider-reported output tokens | `moongate_output_tokens_total` and usage-log output tokens |
| `configured_request_chars` | Serialized request size before overload shaping | `moongate_request_bytes_total` is the transported-byte aggregate, not an exact equivalent |
| `effective_request_chars` | Estimated serialized size after retry shaping | correlate with MoonGate request bytes and retry observations |
| `system_prompt_chars` | Stable system-prompt character count | MoonClaw-only shape diagnostic |
| `tool_schema_chars` | Serialized selected-tool schema size | MoonClaw-only bundle diagnostic |
| `tool_count` | Number of tool schemas sent to the model | MoonClaw-only bundle diagnostic |
| `selected_tool_names` | Tool bundle used for the round | retain only in session/evaluation evidence, never as Prometheus labels |
| `tool_call_count` | Calls selected by the model in the round | MoonClaw-only harness diagnostic |
| `request_compacted` | Retry shaping reduced the message payload | correlate with MoonClaw retry events and MoonGate latency/failure evidence |

The optional `moonclaw.semantic-compaction-trial.v1` record is shadow-only. It
becomes eligible only when the explicit trial flag is set and the preceding
planner transcript has at least 96 messages by default. It records message and
character reduction for offline evaluation; it does not add a model call or
replace the deterministic transcript during the initial trial.

The character counts are diagnostics, not token estimates. Provider-reported
usage is authoritative whenever it is present.

## Cardinality and privacy

MoonGate's `/metrics` endpoint intentionally exposes low-cardinality aggregate
counters and gauges. Prompt text, tool arguments, file paths, model-authored
content, session identifiers, and individual tool names must not become metric
labels. Detailed planner observations belong in bounded MoonClaw session or
benchmark artifacts; MoonGate request logs retain only their existing redacted
correlation and accounting fields.

## Rollout checks

Before enabling a harness experiment for production traffic, compare at least
these cohorts: read-only inspection, small edit with verification, multi-file
edit, UI/browser work, long-running shell output, and a very long task that
crosses the compaction threshold. Record task success, retries, fresh input
tokens, cache-read ratio, completion tokens, request/response bytes, latency,
tool-call count, and verification outcome.

An efficiency change is acceptable only when task and verification success do
not regress. Token or latency improvements alone are insufficient.
