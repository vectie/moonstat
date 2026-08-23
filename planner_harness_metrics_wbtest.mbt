///|
test "moongate aggregates moonclaw planner metrics without labels" {
  let stats = TrafficStats::new()
  assert_true(
    stats.record_planner_metrics({
      "contract": "moonclaw.planner.metrics.v1",
      "tool_call_count": 3,
      "prompt_tokens": 100,
      "completion_tokens": 20,
      "cache_read_tokens": 60,
      "cache_write_tokens": 15,
      "fresh_input_tokens": 40,
      "tool_schema_chars": 900,
      "request_compacted": true,
      "planner_latency_ms": 125,
      "model_retry_count": 2,
      "outcome": "selected",
      "model_transport": "responses",
      "selected_tool_names": ["read", "edit"],
      "session_id": "must-not-be-retained",
    }),
  )
  assert_false(stats.record_planner_metrics({ "contract": "other.v1" }))
  let metrics = stats.prometheus_metrics()
  assert_true(metrics.contains("moongate_planner_rounds_total 1"))
  assert_true(metrics.contains("moongate_planner_cache_read_tokens_total 60"))
  assert_true(metrics.contains("moongate_planner_cache_write_tokens_total 15"))
  assert_true(metrics.contains("moongate_planner_compacted_rounds_total 1"))
  assert_true(metrics.contains("moongate_planner_model_latency_ms_total 125"))
  assert_true(metrics.contains("moongate_planner_model_retries_total 2"))
  assert_true(metrics.contains("moongate_planner_selected_rounds_total 1"))
  assert_true(metrics.contains("moongate_planner_responses_rounds_total 1"))
  assert_false(metrics.contains("must-not-be-retained"))
}

///|
test "moongate planner transport is a closed low-cardinality set" {
  let stats = TrafficStats::new()
  for transport in ["chat_completions", "chat_fallback", "untrusted-value"] {
    assert_true(
      stats.record_planner_metrics({
        "contract": "moonclaw.planner.metrics.v1",
        "model_transport": transport,
      }),
    )
  }
  let metrics = stats.prometheus_metrics()
  assert_true(
    metrics.contains("moongate_planner_chat_completion_rounds_total 1"),
  )
  assert_true(metrics.contains("moongate_planner_chat_fallback_rounds_total 1"))
  assert_false(metrics.contains("untrusted-value"))
}

///|
test "moongate planner telemetry bounds untrusted additive samples" {
  let stats = TrafficStats::new()
  assert_true(
    stats.record_planner_metrics({
      "contract": "moonclaw.planner.metrics.v1",
      "prompt_tokens": 9_000_000_000,
      "cache_write_tokens": -10,
    }),
  )
  let metrics = stats.prometheus_metrics()
  assert_true(
    metrics.contains(
      "moongate_planner_prompt_tokens_total \{PLANNER_HARNESS_METRIC_SAMPLE_MAX}",
    ),
  )
  assert_true(metrics.contains("moongate_planner_cache_write_tokens_total 0"))
}

///|
test "moongate planner outcome is a closed low-cardinality set" {
  let stats = TrafficStats::new()
  assert_true(
    stats.record_planner_metrics({
      "contract": "moonclaw.planner.metrics.v1",
      "outcome": "no_tool_calls",
    }),
  )
  assert_true(
    stats.record_planner_metrics({
      "contract": "moonclaw.planner.metrics.v1",
      "outcome": "attacker-controlled-value",
    }),
  )
  let metrics = stats.prometheus_metrics()
  assert_true(metrics.contains("moongate_planner_no_tool_call_rounds_total 1"))
  assert_false(metrics.contains("attacker-controlled-value"))
}
