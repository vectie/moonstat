///|
pub fn transform_claude_request_for_api_format(
  body : Json,
  api_format : String,
  session_id? : String? = None,
  explicit_prompt_cache_key? : String? = None,
  is_codex_oauth? : Bool = false,
  codex_fast_mode? : Bool = true,
) -> Json {
  match api_format {
    "openai_chat" =>
      anthropic_json_to_openai_chat(body, explicit_prompt_cache_key)
    "openai_responses" => {
      let cache_key = match explicit_prompt_cache_key {
        Some(_) => explicit_prompt_cache_key
        None => session_id
      }
      anthropic_json_to_openai_responses(
        body, cache_key, is_codex_oauth, codex_fast_mode,
      )
    }
    _ => body
  }
}

///|
fn anthropic_json_to_openai_chat(
  body : Json,
  explicit_prompt_cache_key : String?,
) -> Json {
  guard body is Object(obj) else { return body }
  let result : Map[String, Json] = {}
  copy_json_field(obj, result, "model")
  let messages : Array[Json] = []
  append_openai_chat_system_messages(obj, messages)
  append_openai_chat_messages(obj, messages)
  result["messages"] = Json::array(messages)
  let model = json_string_from_map(obj, "model").unwrap_or("")
  if obj.get("max_tokens") is Some(value) {
    if is_openai_o_series_model(model) {
      result["max_completion_tokens"] = value
    } else {
      result["max_tokens"] = value
    }
  }
  copy_json_field(obj, result, "temperature")
  copy_json_field(obj, result, "top_p")
  if obj.get("stop_sequences") is Some(value) {
    result["stop"] = value
  }
  copy_json_field(obj, result, "stream")
  append_openai_chat_tools(obj, result)
  append_openai_chat_tool_choice(obj, result)
  if explicit_prompt_cache_key is Some(key) && !key.trim().is_empty() {
    result["prompt_cache_key"] = Json::string(key)
  }
  inject_openai_stream_include_usage(result)
  Json::object(result)
}

///|
fn anthropic_json_to_openai_responses(
  body : Json,
  cache_key : String?,
  is_codex_oauth : Bool,
  codex_fast_mode : Bool,
) -> Json {
  guard body is Object(obj) else { return body }
  let result : Map[String, Json] = {}
  copy_json_field(obj, result, "model")
  let instructions = anthropic_system_instructions(obj)
  if !instructions.is_empty() {
    result["instructions"] = Json::string(instructions)
  }
  result["input"] = Json::array(anthropic_messages_to_responses_input(obj))
  if obj.get("max_tokens") is Some(value) {
    result["max_output_tokens"] = value
  }
  copy_json_field(obj, result, "temperature")
  copy_json_field(obj, result, "top_p")
  copy_json_field(obj, result, "stream")
  append_openai_responses_tools(obj, result)
  append_openai_responses_tool_choice(obj, result)
  if cache_key is Some(key) && !key.trim().is_empty() {
    result["prompt_cache_key"] = Json::string(key)
  }
  if is_codex_oauth {
    apply_codex_oauth_responses_constraints(result, obj, codex_fast_mode)
  }
  Json::object(result)
}

///|
fn copy_json_field(
  source : Map[String, Json],
  target : Map[String, Json],
  key : String,
) -> Unit {
  if source.get(key) is Some(value) {
    target[key] = value
  }
}

///|
fn is_openai_o_series_model(model : String) -> Bool {
  model.length() > 1 && model[0] == 'o' && model[1] >= 48 && model[1] <= 57
}

///|
fn append_openai_chat_system_messages(
  obj : Map[String, Json],
  messages : Array[Json],
) -> Unit {
  let instructions = anthropic_system_instructions(obj)
  if !instructions.is_empty() {
    messages.push(
      Json::object({
        "role": Json::string("system"),
        "content": Json::string(instructions),
      }),
    )
  }
}

///|
fn anthropic_system_instructions(obj : Map[String, Json]) -> String {
  match obj.get("system") {
    Some(String(text)) => strip_leading_anthropic_billing_header(text)
    Some(Array(items)) => {
      let parts : Array[String] = []
      for item in items {
        match item {
          String(text) => {
            let stripped = strip_leading_anthropic_billing_header(text)
            if !stripped.is_empty() {
              parts.push(stripped)
            }
          }
          Object(system_obj) =>
            if system_obj.get("text") is Some(String(text)) {
              let stripped = strip_leading_anthropic_billing_header(text)
              if !stripped.is_empty() {
                parts.push(stripped)
              }
            }
          _ => ()
        }
      }
      parts.join("\n\n")
    }
    _ => ""
  }
}

///|
fn strip_leading_anthropic_billing_header(text : String) -> String {
  let prefix = "x-anthropic-billing-header:"
  if !text.has_prefix(prefix) {
    return text
  }
  match text.find("\n") {
    Some(index) => text[index + 1:].trim().to_owned()
    None => ""
  }
}

///|
fn append_openai_chat_messages(
  obj : Map[String, Json],
  messages : Array[Json],
) -> Unit {
  guard obj.get("messages") is Some(Array(source_messages)) else { return }
  for message in source_messages {
    guard message is Object(message_obj) else { continue }
    let role = json_string_from_map(message_obj, "role").unwrap_or("user")
    match message_obj.get("content") {
      Some(Array(blocks)) => append_openai_chat_blocks(role, blocks, messages)
      Some(content) =>
        messages.push(
          Json::object({ "role": Json::string(role), "content": content }),
        )
      None =>
        messages.push(
          Json::object({ "role": Json::string(role), "content": Json::null() }),
        )
    }
  }
}

///|
fn append_openai_chat_blocks(
  role : String,
  blocks : Array[Json],
  messages : Array[Json],
) -> Unit {
  let content_parts : Array[Json] = []
  let tool_calls : Array[Json] = []
  for block in blocks {
    guard block is Object(block_obj) else { continue }
    match json_string_from_map(block_obj, "type") {
      Some("text") =>
        if block_obj.get("text") is Some(String(text)) {
          content_parts.push(Json::string(text))
        }
      Some("image") =>
        if block_obj.get("source") is Some(Object(source)) {
          let media_type = json_string_from_map(source, "media_type").unwrap_or(
            "image/png",
          )
          let data = json_string_from_map(source, "data").unwrap_or("")
          content_parts.push(
            Json::object({
              "type": Json::string("image_url"),
              "image_url": Json::object({
                "url": Json::string("data:\{media_type};base64,\{data}"),
              }),
            }),
          )
        }
      Some("tool_use") => tool_calls.push(openai_chat_tool_call(block_obj))
      Some("tool_result") =>
        messages.push(openai_chat_tool_result_message(block_obj))
      _ => ()
    }
  }
  if !content_parts.is_empty() || !tool_calls.is_empty() {
    let message : Map[String, Json] = { "role": Json::string(role) }
    if content_parts.is_empty() {
      message["content"] = Json::null()
    } else if content_parts.length() == 1 {
      message["content"] = content_parts[0]
    } else {
      message["content"] = Json::array(content_parts)
    }
    if !tool_calls.is_empty() {
      message["tool_calls"] = Json::array(tool_calls)
    }
    messages.push(Json::object(message))
  }
}

///|
fn openai_chat_tool_call(block_obj : Map[String, Json]) -> Json {
  let input = block_obj.get("input").unwrap_or(Json::object({}))
  Json::object({
    "id": Json::string(json_string_from_map(block_obj, "id").unwrap_or("")),
    "type": Json::string("function"),
    "function": Json::object({
      "name": Json::string(
        json_string_from_map(block_obj, "name").unwrap_or(""),
      ),
      "arguments": Json::string(input.stringify()),
    }),
  })
}

///|
fn openai_chat_tool_result_message(block_obj : Map[String, Json]) -> Json {
  let content = match block_obj.get("content") {
    Some(String(text)) => text
    Some(json) => json.stringify()
    None => ""
  }
  Json::object({
    "role": Json::string("tool"),
    "tool_call_id": Json::string(
      json_string_from_map(block_obj, "tool_use_id").unwrap_or(""),
    ),
    "content": Json::string(content),
  })
}

///|
fn append_openai_chat_tools(
  obj : Map[String, Json],
  result : Map[String, Json],
) -> Unit {
  guard obj.get("tools") is Some(Array(tools)) else { return }
  let converted : Array[Json] = []
  for tool in tools {
    guard tool is Object(tool_obj) else { continue }
    if json_string_from_map(tool_obj, "type") == Some("BatchTool") {
      continue
    }
    converted.push(
      Json::object({
        "type": Json::string("function"),
        "function": Json::object({
          "name": Json::string(
            json_string_from_map(tool_obj, "name").unwrap_or(""),
          ),
          "description": tool_obj.get("description").unwrap_or(Json::null()),
          "parameters": tool_obj.get("input_schema").unwrap_or(Json::object({})),
        }),
      }),
    )
  }
  if !converted.is_empty() {
    result["tools"] = Json::array(converted)
  }
}

///|
fn append_openai_chat_tool_choice(
  obj : Map[String, Json],
  result : Map[String, Json],
) -> Unit {
  if obj.get("tool_choice") is Some(choice) {
    result["tool_choice"] = map_tool_choice_to_openai_chat(choice)
  }
}

///|
fn map_tool_choice_to_openai_chat(choice : Json) -> Json {
  match choice {
    String("any") => Json::string("required")
    String(_) => choice
    Object(obj) =>
      match json_string_from_map(obj, "type") {
        Some("any") => Json::string("required")
        Some("auto") => Json::string("auto")
        Some("none") => Json::string("none")
        Some("tool") =>
          Json::object({
            "type": Json::string("function"),
            "function": Json::object({
              "name": Json::string(
                json_string_from_map(obj, "name").unwrap_or(""),
              ),
            }),
          })
        _ => Json::object(obj)
      }
    _ => choice
  }
}

///|
fn inject_openai_stream_include_usage(result : Map[String, Json]) -> Unit {
  guard json_bool_from_map(result, "stream").unwrap_or(false) else { return }
  match result.get("stream_options") {
    Some(Object(opts)) => {
      opts["include_usage"] = Json::boolean(true)
      result["stream_options"] = Json::object(opts)
    }
    _ =>
      result["stream_options"] = Json::object({
        "include_usage": Json::boolean(true),
      })
  }
}

///|
fn anthropic_messages_to_responses_input(
  obj : Map[String, Json],
) -> Array[Json] {
  guard obj.get("messages") is Some(Array(source_messages)) else { return [] }
  let input : Array[Json] = []
  for message in source_messages {
    guard message is Object(message_obj) else { continue }
    let role = json_string_from_map(message_obj, "role").unwrap_or("user")
    if message_obj.get("content") is Some(Array(blocks)) {
      append_response_input_blocks(role, blocks, input)
    } else {
      let content = match message_obj.get("content") {
        Some(String(text)) => text
        Some(json) => json.stringify()
        None => ""
      }
      input.push(
        Json::object({
          "role": Json::string(
            if role == "assistant" {
              "assistant"
            } else {
              "user"
            },
          ),
          "content": Json::string(content),
        }),
      )
    }
  }
  input
}

///|
fn append_response_input_blocks(
  role : String,
  blocks : Array[Json],
  input : Array[Json],
) -> Unit {
  let texts : Array[String] = []
  for block in blocks {
    guard block is Object(block_obj) else { continue }
    match json_string_from_map(block_obj, "type") {
      Some("text") =>
        if block_obj.get("text") is Some(String(text)) {
          texts.push(text)
        }
      Some("tool_use") =>
        input.push(
          Json::object({
            "type": Json::string("function_call"),
            "call_id": Json::string(
              json_string_from_map(block_obj, "id").unwrap_or(""),
            ),
            "name": Json::string(
              json_string_from_map(block_obj, "name").unwrap_or(""),
            ),
            "arguments": Json::string(
              block_obj.get("input").unwrap_or(Json::object({})).stringify(),
            ),
          }),
        )
      Some("tool_result") =>
        input.push(
          Json::object({
            "type": Json::string("function_call_output"),
            "call_id": Json::string(
              json_string_from_map(block_obj, "tool_use_id").unwrap_or(""),
            ),
            "output": Json::string(
              block_obj.get("content").unwrap_or(Json::string("")).stringify(),
            ),
          }),
        )
      _ => ()
    }
  }
  if !texts.is_empty() {
    input.push(
      Json::object({
        "role": Json::string(
          if role == "assistant" {
            "assistant"
          } else {
            "user"
          },
        ),
        "content": Json::string(texts.join("\n")),
      }),
    )
  }
}

///|
fn append_openai_responses_tools(
  obj : Map[String, Json],
  result : Map[String, Json],
) -> Unit {
  guard obj.get("tools") is Some(Array(tools)) else { return }
  let converted : Array[Json] = []
  for tool in tools {
    guard tool is Object(tool_obj) else { continue }
    if json_string_from_map(tool_obj, "type") == Some("BatchTool") {
      continue
    }
    converted.push(
      Json::object({
        "type": Json::string("function"),
        "name": Json::string(
          json_string_from_map(tool_obj, "name").unwrap_or(""),
        ),
        "description": tool_obj.get("description").unwrap_or(Json::null()),
        "parameters": tool_obj.get("input_schema").unwrap_or(Json::object({})),
      }),
    )
  }
  if !converted.is_empty() {
    result["tools"] = Json::array(converted)
  }
}

///|
fn append_openai_responses_tool_choice(
  obj : Map[String, Json],
  result : Map[String, Json],
) -> Unit {
  if obj.get("tool_choice") is Some(choice) {
    result["tool_choice"] = map_tool_choice_to_openai_responses(choice)
  }
}

///|
fn map_tool_choice_to_openai_responses(choice : Json) -> Json {
  match choice {
    String("any") => Json::string("required")
    String(_) => choice
    Object(obj) =>
      match json_string_from_map(obj, "type") {
        Some("any") => Json::string("required")
        Some("auto") => Json::string("auto")
        Some("none") => Json::string("none")
        Some("tool") =>
          Json::object({
            "type": Json::string("function"),
            "name": Json::string(
              json_string_from_map(obj, "name").unwrap_or(""),
            ),
          })
        _ => Json::object(obj)
      }
    _ => choice
  }
}

///|
fn apply_codex_oauth_responses_constraints(
  result : Map[String, Json],
  source : Map[String, Json],
  codex_fast_mode : Bool,
) -> Unit {
  result["store"] = Json::boolean(false)
  if codex_fast_mode {
    result["service_tier"] = Json::string("priority")
  } else {
    result.remove("service_tier")
  }
  let marker = Json::string("reasoning.encrypted_content")
  let includes : Array[Json] = match source.get("include") {
    Some(Array(values)) => values
    _ => []
  }
  let mut has_marker = false
  for value in includes {
    if value == marker {
      has_marker = true
    }
  }
  if !has_marker {
    includes.push(marker)
  }
  result["include"] = Json::array(includes)
  result.remove("max_output_tokens")
  result.remove("temperature")
  result.remove("top_p")
  if result.get("instructions") is None {
    result["instructions"] = Json::string("")
  }
  if result.get("tools") is None {
    result["tools"] = Json::array([])
  }
  if result.get("parallel_tool_calls") is None {
    result["parallel_tool_calls"] = Json::boolean(false)
  }
  result["stream"] = Json::boolean(true)
}
