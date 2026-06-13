///|
test "claude session jsonl import mirrors ccs replacement and request log shape" {
  let stats = TrafficStats::new()
  let content =
    #|{"type":"system","sessionId":"session-abc"}
    #|{"type":"assistant","message":{"id":"msg_1","model":"claude-sonnet-4-20250514","usage":{"input_tokens":3,"output_tokens":26,"cache_read_input_tokens":5000,"cache_creation_input_tokens":10000}},"timestamp":"1970-01-01T00:00:10Z"}
    #|{"type":"assistant","message":{"id":"msg_1","model":"claude-sonnet-4-20250514","usage":{"input_tokens":3,"output_tokens":150,"cache_read_input_tokens":5000,"cache_creation_input_tokens":10000},"stop_reason":"end_turn"},"timestamp":"1970-01-01T00:00:10Z"}
  let result = stats.ingest_claude_session_jsonl(
    file_path="/tmp/project/session.jsonl",
    content~,
    last_modified=1L,
  )
  json_inspect(result.to_json(), content={
    "imported": 1,
    "skipped": 0,
    "filesScanned": 1,
    "errors": [],
  })
  assert_eq(stats.request_logs.length(), 1)
  let log = stats.request_logs[0]
  assert_eq(log.request_id, "session:msg_1")
  assert_eq(log.provider_id, "_session")
  assert_eq(log.app_type, "claude")
  assert_eq(log.model, "claude-sonnet-4-20250514")
  assert_eq(log.request_model, Some("claude-sonnet-4-20250514"))
  assert_eq(log.pricing_model, Some("claude-sonnet-4-20250514"))
  assert_eq(log.output_tokens, 150)
  assert_eq(log.cache_read_tokens, 5000)
  assert_eq(log.cache_creation_tokens, 10000)
  assert_eq(log.session_id, Some("session-abc"))
  assert_eq(log.provider_type, Some("session_log"))
  assert_true(log.is_streaming)
  assert_eq(log.status_code, 200)
  assert_eq(log.created_at, 10)
  assert_eq(log.data_source, "session_log")
  assert_eq(log.input_cost_usd, "0.000009")
  assert_eq(log.output_cost_usd, "0.00225")
  assert_eq(log.cache_read_cost_usd, "0.0015")
  assert_eq(log.cache_creation_cost_usd, "0.0375")
  assert_eq(log.total_cost_usd, "0.041259")
}

///|
test "claude session import keeps cache-only billable rows like ccs" {
  let stats = TrafficStats::new()
  let content =
    #|{"type":"assistant","sessionId":"session-cache","message":{"id":"msg_cache","model":"claude-sonnet-4-20250514","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":42,"cache_creation_input_tokens":0}},"timestamp":"1970-01-01T00:00:20+00:00"}
  let result = stats.ingest_claude_session_jsonl(
    file_path="/tmp/project/cache.jsonl",
    content~,
    last_modified=1L,
  )
  assert_eq(result.imported, 1)
  assert_eq(stats.request_logs.length(), 1)
  let log = stats.request_logs[0]
  assert_eq(log.request_id, "session:msg_cache")
  assert_eq(log.input_tokens, 0)
  assert_eq(log.output_tokens, 0)
  assert_eq(log.cache_read_tokens, 42)
  assert_eq(log.created_at, 20)
}

///|
test "claude session import stores offsets and skips duplicate session rows" {
  let stats = TrafficStats::new()
  let file_path = "/tmp/project/dedup.jsonl"
  let first =
    #|{"type":"assistant","message":{"id":"msg_a","model":"unknown","usage":{"input_tokens":1,"output_tokens":2}},"timestamp":"1970-01-01T00:00:30Z"}
  let first_result = stats.ingest_claude_session_jsonl(
    file_path~,
    content=first,
    last_modified=1L,
  )
  assert_eq(first_result.imported, 1)
  let unchanged_result = stats.ingest_claude_session_jsonl(
    file_path~,
    content=first,
    last_modified=1L,
  )
  assert_eq(unchanged_result.imported, 0)
  assert_eq(unchanged_result.skipped, 0)
  let second =
    #|{"type":"assistant","message":{"id":"msg_a","model":"unknown","usage":{"input_tokens":1,"output_tokens":2}},"timestamp":"1970-01-01T00:00:30Z"}
    #|{"type":"assistant","message":{"id":"msg_a","model":"unknown","usage":{"input_tokens":1,"output_tokens":2}},"timestamp":"1970-01-01T00:00:30Z"}
    #|{"type":"assistant","message":{"id":"msg_b","model":"unknown","usage":{"input_tokens":3,"output_tokens":4}},"timestamp":"1970-01-01T00:00:40Z"}
  let second_result = stats.ingest_claude_session_jsonl(
    file_path~,
    content=second,
    last_modified=2L,
  )
  assert_eq(second_result.imported, 1)
  assert_eq(second_result.skipped, 1)
  assert_eq(stats.request_logs.length(), 2)
  assert_eq(stats.request_logs[1].request_id, "session:msg_b")
}

///|
test "session timestamp parser handles offsets" {
  assert_eq(
    parse_session_timestamp_seconds("1970-01-01T08:00:10+08:00"),
    Some(10),
  )
  assert_eq(parse_session_timestamp_seconds("1970-01-01T00:00:10Z"), Some(10))
  assert_eq(parse_session_timestamp_seconds("bad"), None)
}
