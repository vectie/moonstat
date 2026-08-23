# MoonClaw harness metrics at the MoonGate boundary

MoonClaw records per-planner-round prompt, tool, and cache observations under
the `moonclaw.planner.metrics.v1` contract. These observations explain harness
efficiency without changing model requests, routing, cache policy, or tool
execution.

MoonGate remains the source of truth for provider traffic and aggregate usage.
MoonClaw remains the source of truth for the shape of an agent round. Join the
two with the existing request/session correlation evidence; do not copy raw
session IDs, prompts, paths, or tool arguments into Prometheus labels.

MoonGate accepts one additive `POST /usage/planner-metrics` observation at a
time. MoonClaw sends observations only when
`MOONCLAW_PLANNER_METRICS_EXPORT` is explicitly enabled and a validated suite
status advertises MoonGate. It uses a bounded observation timeout and treats
discovery, timeout, rejection, and transport failures as dropped metrics rather
than planner failures. The endpoint validates the
`moonclaw.planner.metrics.v1` contract, folds only allowlisted aggregate fields
into its existing `/metrics` output, and retains no prompt, path, tool-name,
tool-argument, or session fields. Invalid contracts are rejected without
affecting provider traffic accounting.

## Metric mapping

| MoonClaw planner field | Meaning | MoonGate counterpart |
| --- | --- | --- |
| `prompt_tokens` | Provider-reported input tokens, including cache reads | `moongate_input_tokens_total` and usage-log input tokens |
| `cache_read_tokens` | Provider-reported cached input tokens | `moongate_cache_read_tokens_total` and usage-log cache tokens |
| `cache_write_tokens` | Provider-reported input-cache writes when available | `moongate_planner_cache_write_tokens_total`; absent providers contribute zero |
| `fresh_input_tokens` | `max(prompt_tokens - cache_read_tokens, 0)` | derive during joined analysis; do not add a high-cardinality series |
| `cache_read_ratio_ppm` | cached share of input in parts per million | derive for a task or benchmark cohort |
| `completion_tokens` | Provider-reported output tokens | `moongate_output_tokens_total` and usage-log output tokens |
| `configured_request_chars` | Serialized request size before overload shaping | `moongate_request_bytes_total` is the transported-byte aggregate, not an exact equivalent |
| `effective_request_chars` | Estimated serialized size after retry shaping | correlate with MoonGate request bytes and retry observations |
| `configured_request_chars - effective_request_chars` | Characters removed by model-facing projection | `moongate_planner_projection_saved_chars_total`; clamped at zero per round |
| `request_message_count` / `request_message_chars` | Effective model-facing message shape | aggregate counters for cohort averages; never message content |
| `system_prompt_chars` | Stable system-prompt character count | MoonClaw-only shape diagnostic |
| `tool_schema_chars` | Serialized selected-tool schema size | MoonClaw-only bundle diagnostic |
| `tool_count` | Number of tool schemas sent to the model | MoonClaw-only bundle diagnostic |
| `selected_tool_names` | Tool bundle used for the round | retain only in session/evaluation evidence, never as Prometheus labels |
| `tool_call_count` | Calls selected by the model in the round | MoonClaw-only harness diagnostic |
| `planner_latency_ms` | Elapsed planner time observed by the MoonClaw runtime | aggregate total for cohort-average derivation |
| `model_retry_count` | Provider retries when exposed by the planner | aggregate retry counter; currently optional and zero when unavailable |
| `outcome` | Closed `selected` or `no_tool_calls` outcome | separate unlabeled counters; arbitrary values are ignored |
| `model_transport` | Closed `responses`, `chat_completions`, or `chat_fallback` transport outcome | separate unlabeled counters; arbitrary values are ignored |
| `request_compacted` | Retry shaping reduced the message payload | correlate with MoonClaw retry events and MoonGate latency/failure evidence |

The resulting low-cardinality counters are named
`moongate_planner_rounds_total`, `moongate_planner_tool_calls_total`,
`moongate_planner_prompt_tokens_total`,
`moongate_planner_completion_tokens_total`,
`moongate_planner_cache_read_tokens_total`,
`moongate_planner_cache_write_tokens_total`,
`moongate_planner_fresh_input_tokens_total`,
`moongate_planner_tool_schema_chars_total`, and
`moongate_planner_compacted_rounds_total`. Runtime observations add
`moongate_planner_model_latency_ms_total`,
`moongate_planner_model_retries_total`,
`moongate_planner_selected_rounds_total`, and
`moongate_planner_no_tool_call_rounds_total`. Transport observations add
`moongate_planner_responses_rounds_total`,
`moongate_planner_chat_completion_rounds_total`, and
`moongate_planner_chat_fallback_rounds_total`.

Projection accounting additionally exposes
`moongate_planner_configured_request_chars_total`,
`moongate_planner_effective_request_chars_total`,
`moongate_planner_projection_saved_chars_total`,
`moongate_planner_request_messages_total`,
`moongate_planner_request_message_chars_total`,
`moongate_planner_system_prompt_chars_total`, and
`moongate_planner_tools_total`. Cost-oriented cohort analysis uses
`moongate_planner_total_tokens_total`, fresh-input/cache counters, and the sum
of per-round `cache_read_ratio_ppm` divided by the round count. These are
diagnostic aggregates; provider usage logs remain authoritative for billing.

## Responses compatibility route

MoonGate exposes `POST /openclaw/v1/responses` for the MoonClaw Responses
transport experiment. The route is unavailable unless
`MOONGATE_OPENCLAW_RESPONSES_ENABLED` is explicitly truthy. MoonClaw accepts
this route only from a loopback MoonGate base URL and independently keeps its
Responses transport off unless `payload.planner_responses_transport` is true.
Provider-side response storage remains forced off; the transport does not
infer upstream retention authority. Chat Completions fallback is separate and
off by default so transport failures
cannot silently change the experiment cohort.

The compatibility route uses the existing MoonGate provider activation,
routing-session, failover, and usage-accounting path. It does not make prompts,
response IDs, cache keys, or session IDs into metric labels.

The optional `moonclaw.semantic-compaction-trial.v1` record is shadow-only. It
becomes eligible only when the explicit trial flag is set, the preceding
planner transcript has at least 96 messages by default, and the caller supplies
`planner_context_window_tokens` showing at least 75% measured context pressure
by default. Unknown model windows remain ineligible. It records message,
character, estimated-token, and pressure diagnostics for offline evaluation; it
does not add a model call or replace the deterministic transcript during the
initial trial.

The character counts are diagnostics, not token estimates. Provider-reported
usage is authoritative whenever it is present.

## Cardinality and privacy

MoonGate's `/metrics` endpoint intentionally exposes low-cardinality aggregate
counters and gauges. Prompt text, tool arguments, file paths, model-authored
content, session identifiers, and individual tool names must not become metric
labels. Detailed planner observations belong in bounded MoonClaw session or
benchmark artifacts; MoonGate request logs retain only their existing redacted
correlation and accounting fields. Each untrusted additive numeric sample is
clamped to 1,000,000,000 and negative values become zero, preventing one
malformed observation from overflowing or permanently poisoning aggregates.

## Rollout checks

Before enabling a harness experiment for production traffic, compare at least
these cohorts: read-only inspection, small edit with verification, multi-file
edit, UI/browser work, long-running shell output, and a very long task that
crosses the compaction threshold. Record task success, retries, fresh input
tokens, cache-read ratio, completion tokens, request/response bytes, latency,
tool-call count, and verification outcome.

An efficiency change is acceptable only when task and verification success do
not regress. Token or latency improvements alone are insufficient.
