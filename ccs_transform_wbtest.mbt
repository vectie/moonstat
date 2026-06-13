///|
test "ccs openai chat streaming injects include usage" {
  let body = Json::object({
    "model": Json::string("moonshotai/kimi-k2"),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("hello"),
      }),
    ]),
    "max_tokens": Json::number(128.0),
    "stream": Json::boolean(true),
  })
  let transformed = transform_claude_request_for_api_format(body, "openai_chat")
  guard transformed is Object(obj) else { fail("expected object") }
  assert_eq(obj["stream"], Json::boolean(true))
  guard obj["stream_options"] is Object(stream_options) else {
    fail("expected stream options")
  }
  assert_eq(stream_options["include_usage"], Json::boolean(true))
}

///|
test "ccs openai chat non streaming omits stream options" {
  let body = Json::object({
    "model": Json::string("moonshotai/kimi-k2"),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("hello"),
      }),
    ]),
    "max_tokens": Json::number(128.0),
  })
  let transformed = transform_claude_request_for_api_format(body, "openai_chat")
  guard transformed is Object(obj) else { fail("expected object") }
  assert_true(obj.get("stream_options") is None)
}

///|
test "ccs responses transform uses session cache key" {
  let body = Json::object({
    "model": Json::string("gpt-5.4"),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("hello"),
      }),
    ]),
    "max_tokens": Json::number(128.0),
  })
  let transformed = transform_claude_request_for_api_format(
    body,
    "openai_responses",
    session_id=Some("session-123"),
  )
  guard transformed is Object(obj) else { fail("expected object") }
  assert_eq(obj["prompt_cache_key"], Json::string("session-123"))
  assert_true(obj.get("input") is Some(_))
  assert_eq(obj["max_output_tokens"], Json::number(128.0))
}

///|
test "ccs codex oauth responses constraints match ccs" {
  let body = Json::object({
    "model": Json::string("gpt-5.4"),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("hello"),
      }),
    ]),
    "max_tokens": Json::number(128.0),
    "temperature": Json::number(0.2),
    "top_p": Json::number(0.9),
  })
  let transformed = transform_claude_request_for_api_format(
    body,
    "openai_responses",
    session_id=Some("session-123"),
    is_codex_oauth=true,
    codex_fast_mode=false,
  )
  guard transformed is Object(obj) else { fail("expected object") }
  assert_eq(obj["store"], Json::boolean(false))
  assert_eq(obj["stream"], Json::boolean(true))
  assert_eq(
    obj["include"],
    Json::array([Json::string("reasoning.encrypted_content")]),
  )
  assert_eq(obj["prompt_cache_key"], Json::string("session-123"))
  assert_true(obj.get("max_output_tokens") is None)
  assert_true(obj.get("temperature") is None)
  assert_true(obj.get("top_p") is None)
  assert_true(obj.get("service_tier") is None)
  assert_eq(obj["tools"], Json::array([]))
  assert_eq(obj["parallel_tool_calls"], Json::boolean(false))
}

///|
test "ccs transform maps anthropic tool choice" {
  let body = Json::object({
    "model": Json::string("gpt-5.4"),
    "messages": Json::array([]),
    "tool_choice": Json::object({
      "type": Json::string("tool"),
      "name": Json::string("search"),
    }),
  })
  let chat = transform_claude_request_for_api_format(body, "openai_chat")
  guard chat is Object(chat_obj) else { fail("expected object") }
  assert_eq(
    chat_obj["tool_choice"],
    Json::object({
      "type": Json::string("function"),
      "function": Json::object({ "name": Json::string("search") }),
    }),
  )
}
