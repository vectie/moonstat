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
test "codex session import computes cumulative deltas like ccs" {
  let stats = TrafficStats::new()
  let content =
    #|{"type":"session_meta","payload":{"session_id":"codex-s1"}}
    #|{"type":"turn_context","payload":{"model":"OpenAI/GPT-5.5-2026-05-14"}}
    #|{"type":"event_msg","timestamp":"1970-01-01T00:00:10Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":10}}}}
    #|{"type":"event_msg","timestamp":"1970-01-01T00:00:20Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":130,"cached_input_tokens":90,"output_tokens":15}}}}
  let result = stats.ingest_codex_session_jsonl(
    file_path="/tmp/codex/session.jsonl",
    content~,
    last_modified=1L,
  )
  assert_eq(result.imported, 2)
  assert_eq(stats.request_logs.length(), 2)
  let first = stats.request_logs[0]
  assert_eq(first.request_id, "codex_session:codex-s1:1")
  assert_eq(first.provider_id, "_codex_session")
  assert_eq(first.app_type, "codex")
  assert_eq(first.model, "gpt-5.5")
  assert_eq(first.input_tokens, 100)
  assert_eq(first.cache_read_tokens, 60)
  assert_eq(first.output_tokens, 10)
  assert_eq(first.provider_type, Some("codex_session"))
  assert_eq(first.data_source, "codex_session")
  assert_true(first.is_streaming)
  let second = stats.request_logs[1]
  assert_eq(second.request_id, "codex_session:codex-s1:2")
  assert_eq(second.input_tokens, 30)
  assert_eq(second.cache_read_tokens, 30)
  assert_eq(second.output_tokens, 5)
  assert_eq(second.created_at, 20)
}

///|
test "codex session import restores state before offset skip" {
  let stats = TrafficStats::new()
  let file_path = "/tmp/codex/offset.jsonl"
  let first =
    #|{"type":"session_meta","payload":{"session_id":"codex-offset"}}
    #|{"type":"event_msg","timestamp":"1970-01-01T00:00:10Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":1}}}}
  let first_result = stats.ingest_codex_session_jsonl(
    file_path~,
    content=first,
    last_modified=1L,
  )
  assert_eq(first_result.imported, 1)
  let second =
    #|{"type":"session_meta","payload":{"session_id":"codex-offset"}}
    #|{"type":"event_msg","timestamp":"1970-01-01T00:00:10Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":1}}}}
    #|{"type":"event_msg","timestamp":"1970-01-01T00:00:20Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":25,"cached_input_tokens":4,"output_tokens":3}}}}
  let second_result = stats.ingest_codex_session_jsonl(
    file_path~,
    content=second,
    last_modified=2L,
  )
  assert_eq(second_result.imported, 1)
  assert_eq(stats.request_logs.length(), 2)
  let log = stats.request_logs[1]
  assert_eq(log.request_id, "codex_session:codex-offset:2")
  assert_eq(log.input_tokens, 15)
  assert_eq(log.cache_read_tokens, 2)
  assert_eq(log.output_tokens, 2)
}

///|
test "gemini session import merges thoughts into output like ccs" {
  let stats = TrafficStats::new()
  let content =
    #|{
    #|  "sessionId": "gemini-s1",
    #|  "messages": [
    #|    {"type":"user","id":"u1"},
    #|    {"type":"gemini","id":"g1","model":"gemini-3-pro-preview","timestamp":"1970-01-01T00:00:30Z","tokens":{"input":10,"output":2,"cached":1,"thoughts":5}},
    #|    {"type":"gemini","id":"g2","model":"gemini-3-pro-preview","timestamp":"1970-01-01T00:00:40Z","tokens":{"input":0,"output":0,"cached":42,"thoughts":0}}
    #|  ]
    #|}
  let result = stats.ingest_gemini_session_json(
    file_path="/tmp/gemini/session.json",
    content~,
    last_modified=1L,
  )
  assert_eq(result.imported, 2)
  assert_eq(stats.request_logs.length(), 2)
  let first = stats.request_logs[0]
  assert_eq(first.request_id, "gemini_session:gemini-s1:g1")
  assert_eq(first.provider_id, "_gemini_session")
  assert_eq(first.app_type, "gemini")
  assert_eq(first.input_tokens, 10)
  assert_eq(first.output_tokens, 7)
  assert_eq(first.cache_read_tokens, 1)
  assert_eq(first.provider_type, Some("gemini_session"))
  assert_eq(first.data_source, "gemini_session")
  assert_eq(first.created_at, 30)
  let second = stats.request_logs[1]
  assert_eq(second.request_id, "gemini_session:gemini-s1:g2")
  assert_eq(second.cache_read_tokens, 42)
}

///|
test "session imports skip matching proxy log fingerprints" {
  let stats = TrafficStats::new()
  stats.record_request_log(
    RequestLog::new(
      request_id="proxy-1",
      provider_id="codex-oauth",
      app_type="codex",
      model="gpt-5.5",
      usage=TokenUsage::new(
        input_tokens=100,
        output_tokens=10,
        cache_read_tokens=60,
        model=Some("gpt-5.5"),
      ),
      status_code=200,
      created_at=10,
      data_source="proxy",
    ),
  )
  let content =
    #|{"type":"session_meta","payload":{"session_id":"dedup"}}
    #|{"type":"event_msg","timestamp":"1970-01-01T00:00:10Z","payload":{"type":"token_count","info":{"model":"gpt-5.5","total_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":10}}}}
  let result = stats.ingest_codex_session_jsonl(
    file_path="/tmp/codex/dedup.jsonl",
    content~,
    last_modified=1L,
  )
  assert_eq(result.imported, 0)
  assert_eq(result.skipped, 1)
  assert_eq(stats.request_logs.length(), 1)
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
