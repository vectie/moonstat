///|
priv struct OptimizerConfig {
  enabled : Bool
  thinking_optimizer : Bool
  cache_injection : Bool
  cache_ttl : String
}

///|
fn moonstat_optimizer_config_from_env() -> OptimizerConfig {
  {
    enabled: env_bool_default(
      [
        "MOONSTAT_OPTIMIZER_ENABLED", "MOONSTAT_CCS_OPTIMIZER_ENABLED", "CCS_OPTIMIZER_ENABLED",
      ],
      false,
    ),
    thinking_optimizer: env_bool_default(
      [
        "MOONSTAT_THINKING_OPTIMIZER", "MOONSTAT_CCS_THINKING_OPTIMIZER", "CCS_THINKING_OPTIMIZER",
      ],
      true,
    ),
    cache_injection: env_bool_default(
      [
        "MOONSTAT_CACHE_INJECTION", "MOONSTAT_CCS_CACHE_INJECTION", "CCS_CACHE_INJECTION",
      ],
      true,
    ),
    cache_ttl: env_cache_ttl_default(
      ["MOONSTAT_CACHE_TTL", "MOONSTAT_CCS_CACHE_TTL", "CCS_CACHE_TTL"],
      "1h",
    ),
  }
}

///|
fn env_bool_default(keys : Array[String], default : Bool) -> Bool {
  for key in keys {
    match getenv_or_none(key) {
      Some(value) => {
        let normalized = value.trim().to_lower()
        match normalized {
          "1" | "true" | "yes" | "on" => return true
          "0" | "false" | "no" | "off" => return false
          _ => continue
        }
      }
      None => continue
    }
  }
  default
}

///|
fn env_cache_ttl_default(keys : Array[String], default : String) -> String {
  for key in keys {
    match getenv_or_none(key) {
      Some(value) => {
        let trimmed = value.trim().to_owned()
        if trimmed == "5m" || trimmed == "1h" {
          return trimmed
        }
      }
      None => continue
    }
  }
  default
}

///|
fn apply_ccs_optimizer_for_provider(
  body : Json,
  provider : ProviderRouteTarget?,
) -> Json {
  let config = moonstat_optimizer_config_from_env()
  if !config.enabled || !provider_is_bedrock(provider) {
    return body
  }
  // The CCS optimizer config carries this sub-switch next to cache injection.
  // Thinking optimization is ported separately; reading it preserves the shape.
  if config.thinking_optimizer {
    ()
  }
  let mut optimized = body
  if config.cache_injection {
    optimized = inject_ccs_cache_breakpoints(optimized, config.cache_ttl)
  }
  optimized
}

///|
fn provider_is_bedrock(provider : ProviderRouteTarget?) -> Bool {
  guard provider is Some(provider) else { return false }
  guard provider.settings_config is Some(Object(settings)) else { return false }
  guard settings.get("env") is Some(Object(env)) else { return false }
  json_string_from_map(env, "CLAUDE_CODE_USE_BEDROCK") == Some("1")
}

///|
fn inject_ccs_cache_breakpoints(body : Json, cache_ttl : String) -> Json {
  let copied = copy_json(body)
  guard copied is Object(result) else { return copied }
  upgrade_existing_ccs_cache_ttl(result, cache_ttl)
  let existing = count_ccs_cache_breakpoints(Json::object(result))
  let mut budget = 4 - existing
  if budget <= 0 {
    return Json::object(result)
  }
  if budget > 0 && inject_cache_on_last_tool(result, cache_ttl) {
    budget -= 1
  }
  if budget > 0 && inject_cache_on_last_system_block(result, cache_ttl) {
    budget -= 1
  }
  if budget > 0 &&
    inject_cache_on_last_assistant_content_block(result, cache_ttl) {
    budget -= 1
  }
  Json::object(result)
}

///|
fn ccs_cache_control(cache_ttl : String) -> Json {
  let obj : Map[String, Json] = { "type": Json::string("ephemeral") }
  if cache_ttl != "5m" {
    obj["ttl"] = Json::string(cache_ttl)
  }
  Json::object(obj)
}

///|
fn count_ccs_cache_breakpoints(body : Json) -> Int {
  guard body is Object(obj) else { return 0 }
  let mut count = 0
  match obj.get("tools") {
    Some(Array(tools)) =>
      for tool in tools {
        if json_has_cache_control(tool) {
          count += 1
        }
      }
    _ => ()
  }
  match obj.get("system") {
    Some(Array(system)) =>
      for block in system {
        if json_has_cache_control(block) {
          count += 1
        }
      }
    _ => ()
  }
  match obj.get("messages") {
    Some(Array(messages)) =>
      for message in messages {
        guard message is Object(message_obj) else { continue }
        guard message_obj.get("content") is Some(Array(content)) else {
          continue
        }
        for block in content {
          if json_has_cache_control(block) {
            count += 1
          }
        }
      }
    _ => ()
  }
  count
}

///|
fn json_has_cache_control(value : Json) -> Bool {
  match value {
    Object(obj) => obj.get("cache_control") is Some(_)
    _ => false
  }
}

///|
fn copy_json(value : Json) -> Json {
  match value {
    Object(obj) => {
      let result : Map[String, Json] = {}
      for key, child in obj {
        result[key] = copy_json(child)
      }
      Json::object(result)
    }
    Array(items) => {
      let result : Array[Json] = []
      for item in items {
        result.push(copy_json(item))
      }
      Json::array(result)
    }
    _ => value
  }
}

///|
fn upgrade_existing_ccs_cache_ttl(
  obj : Map[String, Json],
  cache_ttl : String,
) -> Unit {
  match obj.get("tools") {
    Some(Array(tools)) =>
      for tool in tools {
        upgrade_block_cache_ttl(tool, cache_ttl)
      }
    _ => ()
  }
  match obj.get("system") {
    Some(Array(system)) =>
      for block in system {
        upgrade_block_cache_ttl(block, cache_ttl)
      }
    _ => ()
  }
  match obj.get("messages") {
    Some(Array(messages)) =>
      for message in messages {
        guard message is Object(message_obj) else { continue }
        guard message_obj.get("content") is Some(Array(content)) else {
          continue
        }
        for block in content {
          upgrade_block_cache_ttl(block, cache_ttl)
        }
      }
    _ => ()
  }
}

///|
fn upgrade_block_cache_ttl(block : Json, cache_ttl : String) -> Unit {
  guard block is Object(block_obj) else { return }
  guard block_obj.get("cache_control") is Some(Object(cache_control)) else {
    return
  }
  let upgraded : Map[String, Json] = {}
  for key, child in cache_control {
    if key != "ttl" {
      upgraded[key] = child
    }
  }
  if cache_ttl != "5m" {
    upgraded["ttl"] = Json::string(cache_ttl)
  }
  block_obj["cache_control"] = Json::object(upgraded)
}

///|
fn inject_cache_on_last_tool(
  obj : Map[String, Json],
  cache_ttl : String,
) -> Bool {
  guard obj.get("tools") is Some(Array(tools)) else { return false }
  guard !tools.is_empty() else { return false }
  let index = tools.length() - 1
  guard tools[index] is Object(tool) else { return false }
  guard tool.get("cache_control") is None else { return false }
  tool["cache_control"] = ccs_cache_control(cache_ttl)
  tools[index] = Json::object(tool)
  obj["tools"] = Json::array(tools)
  true
}

///|
fn inject_cache_on_last_system_block(
  obj : Map[String, Json],
  cache_ttl : String,
) -> Bool {
  let system = match obj.get("system") {
    Some(String(text)) => {
      let converted = [
        Json::object({
          "type": Json::string("text"),
          "text": Json::string(text),
        }),
      ]
      obj["system"] = Json::array(converted)
      converted
    }
    Some(Array(blocks)) => blocks
    _ => return false
  }
  guard !system.is_empty() else { return false }
  let index = system.length() - 1
  guard system[index] is Object(block) else { return false }
  guard block.get("cache_control") is None else { return false }
  block["cache_control"] = ccs_cache_control(cache_ttl)
  system[index] = Json::object(block)
  obj["system"] = Json::array(system)
  true
}

///|
fn inject_cache_on_last_assistant_content_block(
  obj : Map[String, Json],
  cache_ttl : String,
) -> Bool {
  guard obj.get("messages") is Some(Array(messages)) else { return false }
  let mut message_index = messages.length() - 1
  while message_index >= 0 {
    if messages[message_index] is Object(message_obj) &&
      json_string_from_map(message_obj, "role") == Some("assistant") &&
      inject_cache_on_last_non_thinking_block(message_obj, cache_ttl) {
      messages[message_index] = Json::object(message_obj)
      obj["messages"] = Json::array(messages)
      return true
    }
    message_index -= 1
  }
  false
}

///|
fn inject_cache_on_last_non_thinking_block(
  message_obj : Map[String, Json],
  cache_ttl : String,
) -> Bool {
  guard message_obj.get("content") is Some(Array(content)) else { return false }
  let mut index = content.length() - 1
  while index >= 0 {
    guard content[index] is Object(block) else {
      index -= 1
      continue
    }
    let block_type = json_string_from_map(block, "type").unwrap_or("")
    if block_type == "thinking" || block_type == "redacted_thinking" {
      index -= 1
      continue
    }
    guard block.get("cache_control") is None else { return false }
    block["cache_control"] = ccs_cache_control(cache_ttl)
    content[index] = Json::object(block)
    message_obj["content"] = Json::array(content)
    return true
  }
  false
}
