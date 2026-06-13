///|
fn chat_parse_json_for_test(body : String) -> Json {
  @json.parse(body) catch {
    _ => Json::null()
  }
}

///|
test "chat completions request converts to codex responses request" {
  let body = chat_parse_json_for_test(
    (
      #|{
      #|  "model": "client-model",
      #|  "stream": false,
      #|  "messages": [
      #|    { "role": "system", "content": "be concise" },
      #|    { "role": "user", "content": "hi" }
      #|  ],
      #|  "tools": [
      #|    {
      #|      "type": "function",
      #|      "function": {
      #|        "name": "lookup",
      #|        "description": "lookup value",
      #|        "parameters": { "type": "object" }
      #|      }
      #|    }
      #|  ],
      #|  "max_completion_tokens": 123
      #|}
    ),
  )
  let request = openai_chat_to_codex_response_request(body, "gpt-5").unwrap()
  guard request is Object(obj) else { fail("expected object") }
  assert_eq(obj["model"], Json::string("gpt-5"))
  assert_eq(obj["instructions"], Json::string("be concise"))
  assert_eq(obj["max_output_tokens"], Json::number(123.0))
  guard obj["input"] is Array(input) else { fail("expected input") }
  assert_eq(input.length(), 1)
  guard input[0] is Object(first) else { fail("expected message") }
  assert_eq(first["role"], Json::string("user"))
  assert_eq(first["content"], Json::string("hi"))
  guard obj["tools"] is Array(tools) else { fail("expected tools") }
  guard tools[0] is Object(tool) else { fail("expected tool") }
  assert_eq(tool["name"], Json::string("lookup"))
}

///|
test "chat completions request canonicalizes function arguments" {
  let body = chat_parse_json_for_test(
    (
      #|{
      #|  "model": "client-model",
      #|  "messages": [{
      #|    "role": "assistant",
      #|    "tool_calls": [{
      #|      "id": "call_1",
      #|      "type": "function",
      #|      "function": {
      #|        "name": "lookup",
      #|        "arguments": "{ \"z\": 1, \"a\": 2 }"
      #|      }
      #|    }]
      #|  }, {
      #|    "role": "assistant",
      #|    "tool_calls": [{
      #|      "id": "call_2",
      #|      "type": "function",
      #|      "function": {
      #|        "name": "empty",
      #|        "arguments": "  "
      #|      }
      #|    }]
      #|  }]
      #|}
    ),
  )
  let request = openai_chat_to_codex_response_request(body, "gpt-5").unwrap()
  guard request is Object(obj) else { fail("expected object") }
  guard obj["input"] is Array(input) else { fail("expected input") }
  guard input[0] is Object(first) else { fail("expected first") }
  guard input[1] is Object(second) else { fail("expected second") }
  assert_eq(first["arguments"], Json::string("{\"a\":2,\"z\":1}"))
  assert_eq(second["arguments"], Json::string("{}"))
}

///|
test "codex response converts to chat completion response" {
  let body = chat_parse_json_for_test(
    (
      #|{
      #|  "id": "resp_1",
      #|  "output": [
      #|    {
      #|      "type": "message",
      #|      "content": [
      #|        { "type": "output_text", "text": "hello" }
      #|      ]
      #|    }
      #|  ],
      #|  "usage": {
      #|    "input_tokens": 2,
      #|    "output_tokens": 3,
      #|    "input_tokens_details": { "cached_tokens": 1 }
      #|  }
      #|}
    ),
  )
  let response = codex_response_to_openai_chat_completion(body, "client-model")
  guard response is Object(obj) else { fail("expected object") }
  assert_eq(obj["id"], Json::string("resp_1"))
  assert_eq(obj["object"], Json::string("chat.completion"))
  assert_eq(obj["model"], Json::string("client-model"))
  guard obj["choices"] is Array(choices) else { fail("expected choices") }
  guard choices[0] is Object(choice) else { fail("expected choice") }
  guard choice["message"] is Object(message) else { fail("expected message") }
  assert_eq(message["role"], Json::string("assistant"))
  assert_eq(message["content"], Json::string("hello"))
  guard obj["usage"] is Object(usage) else { fail("expected usage") }
  assert_eq(usage["prompt_tokens"], Json::number(2.0))
  assert_eq(usage["completion_tokens"], Json::number(3.0))
  assert_eq(usage["total_tokens"], Json::number(5.0))
}
