///|
fn trim_end_slashes(input : String) -> String {
  let mut output = input
  while output.has_suffix("/") {
    output = output[:output.length() - 1].to_owned()
  }
  output
}

///|
fn trim_start_slashes(input : String) -> String {
  let mut output = input
  while output.has_prefix("/") {
    output = output[1:].to_owned()
  }
  output
}

///|
fn resolve_gemini_native_url(
  base_url : String,
  endpoint : String,
  is_full_url : Bool,
) -> String {
  if !is_full_url || should_normalize_gemini_full_url(base_url) {
    build_gemini_native_url(base_url, endpoint)
  } else {
    let base_url = trim_end_slashes(trim_url_fragment(base_url))
    let (base_without_query, base_query) = split_query(base_url)
    let (_, endpoint_query) = split_query(endpoint)
    match merge_queries(base_query, endpoint_query) {
      Some(query) => "\{base_without_query}?\{query}"
      None => base_without_query
    }
  }
}

///|
fn build_gemini_native_url(base_url : String, endpoint : String) -> String {
  let base_url = trim_end_slashes(trim_url_fragment(base_url))
  let (base_without_query, base_query) = split_query(base_url)
  let (endpoint_without_query, endpoint_query) = split_query(endpoint)
  let endpoint_path = "/\{trim_start_slashes(endpoint_without_query)}"
  let (origin, raw_path) = split_origin_and_path(base_without_query)
  let prefix_path = normalize_gemini_base_path(raw_path)
  let url = if prefix_path.is_empty() {
    "\{origin}\{endpoint_path}"
  } else {
    "\{origin}\{prefix_path}\{endpoint_path}"
  }
  match merge_queries(base_query, endpoint_query) {
    Some(query) => "\{url}?\{query}"
    None => url
  }
}

///|
fn should_normalize_gemini_full_url(base_url : String) -> Bool {
  let base_url = trim_end_slashes(trim_url_fragment(base_url))
  let (base_without_query, _) = split_query(base_url)
  let (origin, path) = split_origin_and_path(base_without_query)
  if path.is_empty() || path == "/" {
    return true
  }
  let path = trim_end_slashes(path)
  let on_google_host = is_google_gemini_host(extract_host(origin))
  if matches_vertex_ai_publisher_model_path(path) {
    return false
  }
  if matches_structured_gemini_models_path(path) ||
    path.has_suffix("/v1beta/openai/chat/completions") ||
    path.has_suffix("/v1beta/openai/responses") ||
    path.has_suffix("/openai/chat/completions") ||
    path.has_suffix("/openai/responses") ||
    path.has_suffix("/v1/openai/chat/completions") ||
    path.has_suffix("/v1/openai/responses") {
    return true
  }
  on_google_host &&
  (
    path.has_suffix("/v1beta") ||
    path.has_suffix("/v1beta/models") ||
    path.has_suffix("/v1beta/openai") ||
    path.has_suffix("/v1") ||
    path.has_suffix("/v1/models") ||
    path.has_suffix("/models") ||
    path.has_suffix("/v1/openai") ||
    path.has_suffix("/openai")
  )
}

///|
fn trim_url_fragment(input : String) -> String {
  match input.find("#") {
    Some(index) => input[:index].to_owned()
    None => input
  }
}

///|
fn split_query(input : String) -> (String, String?) {
  match input.find("?") {
    Some(index) =>
      (input[:index].to_owned(), Some(input[index + 1:].to_owned()))
    None => (input, None)
  }
}

///|
fn split_origin_and_path(base_url : String) -> (String, String) {
  match base_url.find("://") {
    None => (base_url, "")
    Some(scheme_index) => {
      let authority_start = scheme_index + 3
      let rest = base_url[authority_start:]
      match rest.find("/") {
        None => (base_url, "")
        Some(path_start_rel) => {
          let path_start = authority_start + path_start_rel
          (base_url[:path_start].to_owned(), base_url[path_start:].to_owned())
        }
      }
    }
  }
}

///|
fn normalize_gemini_base_path(path : String) -> String {
  let path = trim_end_slashes(path)
  if path.is_empty() || path == "/" {
    return ""
  }
  for marker in ["/v1beta/models/", "/v1/models/", "/models/"] {
    if path.find(marker) is Some(index) {
      return normalize_prefix(path[:index].to_owned())
    }
  }
  for
    suffix in [
      "/v1beta/openai/chat/completions", "/v1/openai/chat/completions", "/openai/chat/completions",
      "/v1beta/openai/responses", "/v1/openai/responses", "/openai/responses", "/v1beta/openai",
      "/v1/openai", "/openai", "/v1beta/models", "/v1/models", "/models", "/v1beta",
      "/v1",
    ] {
    if path == suffix {
      return ""
    }
    if path.has_suffix(suffix) {
      return normalize_prefix(path[:path.length() - suffix.length()].to_owned())
    }
  }
  path
}

///|
fn normalize_prefix(prefix : String) -> String {
  let prefix = trim_end_slashes(prefix)
  if prefix.is_empty() || prefix == "/" {
    ""
  } else {
    prefix
  }
}

///|
fn extract_host(origin : String) -> String {
  let after_scheme = match origin.find("://") {
    Some(index) => origin[index + 3:]
    None => origin
  }
  let without_userinfo = match after_scheme.rev_find("@") {
    Some(index) => after_scheme[index + 1:]
    None => after_scheme
  }
  let without_port = match without_userinfo.find(":") {
    Some(index) => without_userinfo[:index]
    None => without_userinfo
  }
  trim_end_slashes(without_port.to_owned())
}

///|
fn is_google_gemini_host(host : String) -> Bool {
  if host.is_empty() {
    return false
  }
  let host_lower = host.to_lower()
  host_lower == "generativelanguage.googleapis.com" ||
  host_lower == "aiplatform.googleapis.com" ||
  host_lower.has_suffix("-aiplatform.googleapis.com")
}

///|
fn matches_structured_gemini_models_path(path : String) -> Bool {
  let mut cursor = path
  while cursor.find("/models/") is Some(index) {
    let after = cursor[index + "/models/".length():]
    if after.contains(":generateContent") ||
      after.contains(":streamGenerateContent") {
      return true
    }
    cursor = after.to_owned()
  }
  false
}

///|
fn matches_vertex_ai_publisher_model_path(path : String) -> Bool {
  match (path.find("/projects/"), path.find("/publishers/google/models/")) {
    (Some(projects_index), Some(publisher_models_index)) => {
      if projects_index >= publisher_models_index ||
        !path[projects_index:publisher_models_index].contains("/locations/") {
        return false
      }
      let after_model = path[publisher_models_index +
        "/publishers/google/models/".length():]
      after_model.contains(":generateContent") ||
      after_model.contains(":streamGenerateContent")
    }
    _ => false
  }
}

///|
fn merge_queries(base_query : String?, endpoint_query : String?) -> String? {
  match (base_query, endpoint_query) {
    (None, None) => None
    (Some(base), None) => Some(base)
    (None, Some(endpoint)) => Some(endpoint)
    (Some(base), Some(endpoint)) =>
      if base.is_empty() {
        Some(endpoint)
      } else if endpoint.is_empty() {
        Some(base)
      } else {
        Some("\{base}&\{endpoint}")
      }
  }
}
