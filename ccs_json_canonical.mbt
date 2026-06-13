///|
fn canonicalize_json_value(value : Json) -> Json {
  match value {
    Array(values) =>
      Json::array(values.map(fn(value) { canonicalize_json_value(value) }))
    Object(obj) => {
      let keys = obj.keys().collect()
      keys.sort_by(ascii_lex_compare)
      let sorted : Map[String, Json] = {}
      for key in keys {
        match obj.get(key) {
          Some(value) => sorted[key] = canonicalize_json_value(value)
          None => ()
        }
      }
      Json::object(sorted)
    }
    _ => value
  }
}

///|
fn canonical_json_string(value : Json) -> String {
  canonicalize_json_value(value).stringify()
}

///|
fn canonicalize_json_string_if_parseable(value : String) -> String {
  let trimmed = value.trim()
  if trimmed.is_empty() {
    return value
  }
  let parsed = @json.parse(trimmed) catch { _ => return value }
  canonical_json_string(parsed)
}

///|
fn canonicalize_tool_arguments_string(value : String) -> String {
  if value.trim().is_empty() {
    return "{}"
  }
  canonicalize_json_string_if_parseable(value)
}

///|
fn canonicalize_tool_arguments(value : Json?) -> String {
  match value {
    Some(String(value)) => canonicalize_tool_arguments_string(value)
    Some(value) => canonical_json_string(value)
    None => "{}"
  }
}
