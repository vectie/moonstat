///|
pub struct TokenUsage {
  input_tokens : Int
  output_tokens : Int
  cache_read_tokens : Int
  cache_creation_tokens : Int
  model : String?
  message_id : String?
}

///|
pub fn TokenUsage::new(
  input_tokens~ : Int,
  output_tokens~ : Int,
  cache_read_tokens? : Int = 0,
  cache_creation_tokens? : Int = 0,
  model? : String? = None,
  message_id? : String? = None,
) -> TokenUsage {
  {
    input_tokens,
    output_tokens,
    cache_read_tokens,
    cache_creation_tokens,
    model,
    message_id,
  }
}

///|
pub fn TokenUsage::empty() -> TokenUsage {
  TokenUsage::new(input_tokens=0, output_tokens=0)
}

///|
pub fn TokenUsage::has_billable_tokens(self : TokenUsage) -> Bool {
  self.input_tokens > 0 ||
  self.output_tokens > 0 ||
  self.cache_read_tokens > 0 ||
  self.cache_creation_tokens > 0
}

///|
pub fn TokenUsage::anthropic_input_tokens(self : TokenUsage) -> Int {
  max_int(
    self.input_tokens - self.cache_read_tokens - self.cache_creation_tokens,
    0,
  )
}

///|
pub fn token_usage_from_claude_response(body : Json) -> TokenUsage? {
  guard body is Object(obj) else { return None }
  guard obj.get("usage") is Some(Object(usage)) else { return None }
  let input_tokens = json_int(usage, "input_tokens")
  let output_tokens = json_int(usage, "output_tokens")
  if input_tokens is None || output_tokens is None {
    return None
  }
  Some(
    TokenUsage::new(
      input_tokens=input_tokens.unwrap(),
      output_tokens=output_tokens.unwrap(),
      cache_read_tokens=json_int_or_zero(usage, "cache_read_input_tokens"),
      cache_creation_tokens=json_int_or_zero(
        usage, "cache_creation_input_tokens",
      ),
      model=json_string(obj, "model"),
      message_id=json_string(obj, "id"),
    ),
  )
}

///|
pub fn token_usage_from_codex_response(body : Json) -> TokenUsage? {
  guard body is Object(obj) else { return None }
  guard obj.get("usage") is Some(Object(usage)) else { return None }
  let input_tokens = json_int(usage, "input_tokens")
  let output_tokens = json_int(usage, "output_tokens")
  if input_tokens is None || output_tokens is None {
    return None
  }
  let cache_read_tokens = match json_int(usage, "cache_read_input_tokens") {
    Some(n) => n
    None =>
      match usage.get("input_tokens_details") {
        Some(Object(details)) => json_int_or_zero(details, "cached_tokens")
        _ => 0
      }
  }
  Some(
    TokenUsage::new(
      input_tokens=input_tokens.unwrap(),
      output_tokens=output_tokens.unwrap(),
      cache_read_tokens~,
      cache_creation_tokens=json_int_or_zero(
        usage, "cache_creation_input_tokens",
      ),
      model=json_string(obj, "model"),
    ),
  )
}

///|
pub fn token_usage_from_openai_response(body : Json) -> TokenUsage? {
  guard body is Object(obj) else { return None }
  guard obj.get("usage") is Some(Object(usage)) else { return None }
  let input_tokens = json_int(usage, "prompt_tokens")
  let output_tokens = json_int(usage, "completion_tokens")
  if input_tokens is None || output_tokens is None {
    return None
  }
  let cache_read_tokens = match usage.get("prompt_tokens_details") {
    Some(Object(details)) => json_int_or_zero(details, "cached_tokens")
    _ => 0
  }
  Some(
    TokenUsage::new(
      input_tokens=input_tokens.unwrap(),
      output_tokens=output_tokens.unwrap(),
      cache_read_tokens~,
      model=json_string(obj, "model"),
    ),
  )
}

///|
pub fn token_usage_from_codex_response_auto(body : Json) -> TokenUsage? {
  guard body is Object(obj) else { return None }
  guard obj.get("usage") is Some(Object(usage)) else { return None }
  if usage.get("prompt_tokens") is Some(_) {
    token_usage_from_openai_response(body)
  } else if usage.get("input_tokens") is Some(_) {
    token_usage_from_codex_response(body)
  } else {
    None
  }
}

///|
pub fn token_usage_from_gemini_response(body : Json) -> TokenUsage? {
  guard body is Object(obj) else { return None }
  guard obj.get("usageMetadata") is Some(Object(usage)) else { return None }
  let prompt_tokens = json_int(usage, "promptTokenCount")
  let total_tokens = json_int(usage, "totalTokenCount")
  if prompt_tokens is None || total_tokens is None {
    return None
  }
  let input_tokens = prompt_tokens.unwrap()
  let output_tokens = max_int(total_tokens.unwrap() - input_tokens, 0)
  Some(
    TokenUsage::new(
      input_tokens~,
      output_tokens~,
      cache_read_tokens=json_int_or_zero(usage, "cachedContentTokenCount"),
      model=json_string(obj, "modelVersion"),
    ),
  )
}

///|
fn json_int(obj : Map[String, Json], key : String) -> Int? {
  match obj.get(key) {
    Some(Number(n, ..)) => Some(n.trunc().to_int())
    _ => None
  }
}

///|
fn json_int_or_zero(obj : Map[String, Json], key : String) -> Int {
  match json_int(obj, key) {
    Some(n) => n
    None => 0
  }
}

///|
fn json_string(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn max_int(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}
