///|
fn parse_json_for_test(body : String) -> Json {
  let parsed : Result[Json, Error] = try? @json.parse(body)
  match parsed {
    Ok(json) => json
    Err(_) => Json::null()
  }
}

///|
test "claude usage preserves cache-only billable tokens" {
  let body =
    #|{
    #|  "id": "msg_1",
    #|  "model": "claude-sonnet",
    #|  "usage": {
    #|    "input_tokens": 0,
    #|    "output_tokens": 0,
    #|    "cache_read_input_tokens": 42,
    #|    "cache_creation_input_tokens": 0
    #|  }
    #|}
  let usage = token_usage_from_claude_response(parse_json_for_test(body)).unwrap()
  assert_eq(usage.input_tokens, 0)
  assert_eq(usage.output_tokens, 0)
  assert_eq(usage.cache_read_tokens, 42)
  assert_eq(usage.message_id, Some("msg_1"))
  assert_true(usage.has_billable_tokens())
}

///|
test "codex usage reads cached tokens from details" {
  let body =
    #|{
    #|  "model": "gpt-5",
    #|  "usage": {
    #|    "input_tokens": 100,
    #|    "output_tokens": 7,
    #|    "input_tokens_details": { "cached_tokens": 31 },
    #|    "cache_creation_input_tokens": 5
    #|  }
    #|}
  let usage = token_usage_from_codex_response_auto(parse_json_for_test(body)).unwrap()
  assert_eq(usage.input_tokens, 100)
  assert_eq(usage.output_tokens, 7)
  assert_eq(usage.cache_read_tokens, 31)
  assert_eq(usage.cache_creation_tokens, 5)
  assert_eq(usage.anthropic_input_tokens(), 64)
  assert_eq(usage.model, Some("gpt-5"))
}

///|
test "openai usage maps prompt and completion tokens" {
  let body =
    #|{
    #|  "model": "gpt-4.1",
    #|  "usage": {
    #|    "prompt_tokens": 12,
    #|    "completion_tokens": 8,
    #|    "prompt_tokens_details": { "cached_tokens": 4 }
    #|  }
    #|}
  let usage = token_usage_from_codex_response_auto(parse_json_for_test(body)).unwrap()
  assert_eq(usage.input_tokens, 12)
  assert_eq(usage.output_tokens, 8)
  assert_eq(usage.cache_read_tokens, 4)
  assert_eq(usage.anthropic_input_tokens(), 8)
}

///|
test "anthropic usage input clamps when cache exceeds input" {
  let usage = TokenUsage::new(
    input_tokens=100,
    output_tokens=50,
    cache_read_tokens=80,
    cache_creation_tokens=50,
  )
  assert_eq(usage.anthropic_input_tokens(), 0)
}

///|
test "gemini usage derives output from total minus prompt" {
  let body =
    #|{
    #|  "modelVersion": "gemini-2.5-pro",
    #|  "usageMetadata": {
    #|    "promptTokenCount": 20,
    #|    "totalTokenCount": 55,
    #|    "cachedContentTokenCount": 9
    #|  }
    #|}
  let usage = token_usage_from_gemini_response(parse_json_for_test(body)).unwrap()
  assert_eq(usage.input_tokens, 20)
  assert_eq(usage.output_tokens, 35)
  assert_eq(usage.cache_read_tokens, 9)
  assert_eq(usage.model, Some("gemini-2.5-pro"))
}
