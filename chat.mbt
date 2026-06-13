///|
priv struct ChatCompletionOutput {
  content : String
  tool_calls : Array[Json]
}

///|
fn openai_chat_model(body : Json) -> String? {
  guard body is Object(obj) else { return None }
  match obj.get("model") {
    Some(String(model)) => Some(model)
    _ => None
  }
}

///|
fn openai_chat_to_codex_response_request(
  body : Json,
  upstream_model : String,
) -> Json? {
  guard body is Object(obj) else { return None }
  guard obj.get("messages") is Some(Array(messages)) else { return None }
  let input_items : Array[Json] = []
  let instructions : Array[String] = []
  for message in messages {
    append_chat_message_as_response_item(message, input_items, instructions)
  }
  let request : Map[String, Json] = {
    "model": Json::string(upstream_model),
    "input": Json::array(input_items),
    "store": Json::boolean(false),
    "stream": Json::boolean(json_bool_from_map(obj, "stream").unwrap_or(false)),
  }
  if !instructions.is_empty() {
    request["instructions"] = Json::string(instructions.join("\n\n"))
  }
  if obj.get("max_completion_tokens") is Some(value) {
    request["max_output_tokens"] = value
  } else if obj.get("max_tokens") is Some(value) {
    request["max_output_tokens"] = value
  }
  for key in ["temperature", "top_p", "metadata", "reasoning"] {
    if obj.get(key) is Some(value) {
      request[key] = value
    }
  }
  if obj.get("tools") is Some(Array(tools)) {
    let codex_tools : Array[Json] = []
    for tool in tools {
      if openai_tool_to_codex_tool(tool) is Some(codex_tool) {
        codex_tools.push(codex_tool)
      }
    }
    if !codex_tools.is_empty() {
      request["tools"] = Json::array(codex_tools)
    }
  }
  if obj.get("tool_choice") is Some(value) {
    request["tool_choice"] = openai_tool_choice_to_codex(value)
  }
  Some(Json::object(request))
}

///|
fn append_chat_message_as_response_item(
  message : Json,
  input_items : Array[Json],
  instructions : Array[String],
) -> Unit {
  guard message is Object(obj) else { return }
  let role = match obj.get("role") {
    Some(String(role)) => role
    _ => "user"
  }
  if role == "system" || role == "developer" {
    let text = chat_content_to_text(
      obj.get("content").unwrap_or(Json::string("")),
    )
    if !text.trim().is_empty() {
      instructions.push(text)
    }
    return
  }
  if role == "tool" {
    let item : Map[String, Json] = {
      "type": Json::string("function_call_output"),
      "call_id": Json::string(
        json_string_from_map(obj, "tool_call_id").unwrap_or(""),
      ),
      "output": Json::string(
        chat_content_to_text(obj.get("content").unwrap_or(Json::string(""))),
      ),
    }
    input_items.push(Json::object(item))
    return
  }
  let response_role = if role == "assistant" { "assistant" } else { "user" }
  let content = chat_content_to_text(
    obj.get("content").unwrap_or(Json::string("")),
  )
  if !content.trim().is_empty() || role != "assistant" {
    input_items.push(
      Json::object({
        "role": Json::string(response_role),
        "content": Json::string(content),
      }),
    )
  }
  if obj.get("tool_calls") is Some(Array(tool_calls)) {
    for tool_call in tool_calls {
      if openai_tool_call_to_response_item(tool_call) is Some(item) {
        input_items.push(item)
      }
    }
  }
}

///|
fn chat_content_to_text(content : Json) -> String {
  match content {
    String(text) => text
    Array(parts) => {
      let texts : Array[String] = []
      for part in parts {
        match part {
          String(text) => texts.push(text)
          Object(obj) =>
            if obj.get("text") is Some(String(text)) {
              texts.push(text)
            } else if obj.get("type") is Some(String("text")) &&
              obj.get("content") is Some(String(text)) {
              texts.push(text)
            }
          _ => ()
        }
      }
      texts.join("\n")
    }
    _ => ""
  }
}

///|
fn openai_tool_to_codex_tool(tool : Json) -> Json? {
  guard tool is Object(obj) else { return None }
  if obj.get("type") is Some(String("function")) &&
    obj.get("function") is Some(Object(function)) {
    let name = json_string_from_map(function, "name").unwrap_or("")
    if name.trim().is_empty() {
      return None
    }
    let result : Map[String, Json] = {
      "type": Json::string("function"),
      "name": Json::string(name),
      "parameters": function.get("parameters").unwrap_or(Json::object({})),
    }
    if function.get("description") is Some(String(description)) {
      result["description"] = Json::string(description)
    }
    return Some(Json::object(result))
  }
  if obj.get("name") is Some(String(_)) {
    return Some(tool)
  }
  None
}

///|
fn openai_tool_choice_to_codex(choice : Json) -> Json {
  match choice {
    String("auto") | String("none") | String("required") => choice
    Object(obj) =>
      if obj.get("type") is Some(String("function")) &&
        obj.get("function") is Some(Object(function)) {
        Json::object({
          "type": Json::string("function"),
          "name": Json::string(
            json_string_from_map(function, "name").unwrap_or(""),
          ),
        })
      } else {
        Json::object(obj)
      }
    _ => choice
  }
}

///|
fn openai_tool_call_to_response_item(tool_call : Json) -> Json? {
  guard tool_call is Object(obj) else { return None }
  guard obj.get("function") is Some(Object(function)) else { return None }
  let name = json_string_from_map(function, "name").unwrap_or("")
  if name.trim().is_empty() {
    return None
  }
  let call_id = json_string_from_map(obj, "id").unwrap_or(
    generate_chat_completion_id(),
  )
  Some(
    Json::object({
      "type": Json::string("function_call"),
      "call_id": Json::string(call_id),
      "name": Json::string(name),
      "arguments": Json::string(
        json_string_from_map(function, "arguments").unwrap_or("{}"),
      ),
    }),
  )
}

///|
fn codex_response_to_openai_chat_completion(
  body : Json,
  model : String,
) -> Json {
  let output = extract_chat_completion_output(body)
  let usage = token_usage_from_codex_response_auto(body).unwrap_or(
    TokenUsage::empty(),
  )
  let message : Map[String, Json] = { "role": Json::string("assistant") }
  if output.tool_calls.is_empty() {
    message["content"] = Json::string(output.content)
  } else {
    message["content"] = Json::null()
    message["tool_calls"] = Json::array(output.tool_calls)
  }
  let finish_reason = if output.tool_calls.is_empty() {
    "stop"
  } else {
    "tool_calls"
  }
  Json::object({
    "id": Json::string(
      codex_response_id(body).unwrap_or(generate_chat_completion_id()),
    ),
    "object": Json::string("chat.completion"),
    "created": Json::number((@async.now().to_int() / 1000).to_double()),
    "model": Json::string(model),
    "choices": Json::array([
      Json::object({
        "index": Json::number(0.0),
        "message": Json::object(message),
        "finish_reason": Json::string(finish_reason),
      }),
    ]),
    "usage": openai_usage_json(usage),
  })
}

///|
fn openai_chat_role_chunk(id : String, model : String, created : Int) -> Json {
  Json::object({
    "id": Json::string(id),
    "object": Json::string("chat.completion.chunk"),
    "created": Json::number(created.to_double()),
    "model": Json::string(model),
    "choices": Json::array([
      Json::object({
        "index": Json::number(0.0),
        "delta": Json::object({ "role": Json::string("assistant") }),
        "finish_reason": Json::null(),
      }),
    ]),
  })
}

///|
fn codex_stream_event_to_openai_chat_chunk(
  data : String,
  id : String,
  model : String,
  created : Int,
) -> Json? {
  let parsed = @json.parse(data) catch { _ => return None }
  guard parsed is Object(obj) else { return None }
  match obj.get("type") {
    Some(String("response.output_text.delta")) => {
      let delta = json_string_from_map(obj, "delta").unwrap_or("")
      Some(
        openai_chat_delta_chunk(
          id,
          model,
          created,
          { "content": Json::string(delta) },
          Json::null(),
        ),
      )
    }
    Some(String("response.output_item.done")) =>
      match obj.get("item") {
        Some(Object(item)) =>
          if item.get("type") is Some(String("function_call")) {
            Some(
              openai_chat_delta_chunk(
                id,
                model,
                created,
                {
                  "tool_calls": Json::array([
                    openai_tool_call_delta_from_response_item(item),
                  ]),
                },
                Json::null(),
              ),
            )
          } else {
            None
          }
        _ => None
      }
    Some(String("response.completed")) =>
      Some(
        openai_chat_delta_chunk(id, model, created, {}, Json::string("stop")),
      )
    _ => None
  }
}

///|
fn openai_chat_delta_chunk(
  id : String,
  model : String,
  created : Int,
  delta : Map[String, Json],
  finish_reason : Json,
) -> Json {
  Json::object({
    "id": Json::string(id),
    "object": Json::string("chat.completion.chunk"),
    "created": Json::number(created.to_double()),
    "model": Json::string(model),
    "choices": Json::array([
      Json::object({
        "index": Json::number(0.0),
        "delta": Json::object(delta),
        "finish_reason": finish_reason,
      }),
    ]),
  })
}

///|
fn extract_chat_completion_output(body : Json) -> ChatCompletionOutput {
  let mut content = ""
  let tool_calls : Array[Json] = []
  guard body is Object(obj) else { return { content, tool_calls } }
  if obj.get("output_text") is Some(String(text)) {
    content = text
  }
  if obj.get("output") is Some(Array(outputs)) {
    for output in outputs {
      guard output is Object(item) else { continue }
      match item.get("type") {
        Some(String("message")) =>
          content += extract_response_message_text(item)
        Some(String("function_call")) =>
          tool_calls.push(openai_tool_call_from_response_item(item))
        _ => ()
      }
    }
  }
  { content, tool_calls }
}

///|
fn extract_response_message_text(item : Map[String, Json]) -> String {
  let texts : Array[String] = []
  if item.get("content") is Some(Array(parts)) {
    for part in parts {
      guard part is Object(part_obj) else { continue }
      if part_obj.get("type") is Some(String("output_text")) &&
        part_obj.get("text") is Some(String(text)) {
        texts.push(text)
      }
    }
  }
  texts.join("")
}

///|
fn openai_tool_call_from_response_item(item : Map[String, Json]) -> Json {
  Json::object({
    "id": Json::string(
      json_string_from_map(item, "call_id").unwrap_or(
        generate_chat_completion_id(),
      ),
    ),
    "type": Json::string("function"),
    "function": Json::object({
      "name": Json::string(
        json_string_from_map(item, "name").unwrap_or("unknown"),
      ),
      "arguments": Json::string(
        json_string_from_map(item, "arguments").unwrap_or("{}"),
      ),
    }),
  })
}

///|
fn openai_tool_call_delta_from_response_item(item : Map[String, Json]) -> Json {
  Json::object({
    "index": Json::number(0.0),
    "id": Json::string(
      json_string_from_map(item, "call_id").unwrap_or(
        generate_chat_completion_id(),
      ),
    ),
    "type": Json::string("function"),
    "function": Json::object({
      "name": Json::string(
        json_string_from_map(item, "name").unwrap_or("unknown"),
      ),
      "arguments": Json::string(
        json_string_from_map(item, "arguments").unwrap_or("{}"),
      ),
    }),
  })
}

///|
fn openai_usage_json(usage : TokenUsage) -> Json {
  Json::object({
    "prompt_tokens": Json::number(usage.input_tokens.to_double()),
    "completion_tokens": Json::number(usage.output_tokens.to_double()),
    "total_tokens": Json::number(
      (usage.input_tokens + usage.output_tokens).to_double(),
    ),
    "prompt_tokens_details": Json::object({
      "cached_tokens": Json::number(usage.cache_read_tokens.to_double()),
    }),
  })
}

///|
fn codex_response_id(body : Json) -> String? {
  guard body is Object(obj) else { return None }
  json_string_from_map(obj, "id")
}

///|
fn json_bool_from_map(obj : Map[String, Json], key : String) -> Bool? {
  match obj.get(key) {
    Some(true) => Some(true)
    Some(false) => Some(false)
    _ => None
  }
}

///|
fn json_string_from_map(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn generate_chat_completion_id() -> String {
  let gen = @uuid.generator(@random.Rand::new())
  let uuid = gen.v4()
  "chatcmpl_\{uuid}"
}
