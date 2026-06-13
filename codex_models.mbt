///|
const CODEX_OAUTH_MODELS_ENDPOINT = "/backend-api/codex/models?client_version=1.0.0"

///|
priv struct CodexModel {
  id : String
  owned_by : String
}

///|
fn CodexModel::to_openai_json(self : CodexModel) -> Json {
  {
    "id": Json::string(self.id),
    "object": Json::string("model"),
    "owned_by": Json::string(self.owned_by),
  }.to_json()
}

///|
fn CodexModel::to_moonstat_json(self : CodexModel) -> Json {
  {
    "id": Json::string(self.id),
    "name": Json::string(self.id),
    "provider": Json::string("codex-oauth"),
    "owned_by": Json::string(self.owned_by),
  }.to_json()
}

///|
fn static_codex_models(default_model : String) -> Array[CodexModel] {
  [{ id: default_model, owned_by: "moonstat" }]
}

///|
async fn fetch_codex_oauth_models(
  creds : @codex.Credentials,
) -> Result[Array[CodexModel], String] {
  let client = @http.Client::new("https://chatgpt.com", headers={
    "Authorization": "Bearer \{creds.accessToken}",
    "ChatGPT-Account-ID": creds.accountId,
    "Accept": "application/json",
    "originator": "moonstat_gateway",
    "User-Agent": "moonstat/1.0.0",
  })
  defer client.close()
  try {
    let response = client.get(CODEX_OAUTH_MODELS_ENDPOINT)
    let body = client.read_all().text()
    if response.code is (200..=299) {
      Ok(parse_codex_oauth_models(@json.parse(body)))
    } else {
      Err("HTTP \{response.code}: \{truncate_error_body(body)}")
    }
  } catch {
    err => Err("request failed: \{err}")
  }
}

///|
fn parse_codex_oauth_models(value : Json) -> Array[CodexModel] {
  let models : Array[CodexModel] = []
  match value {
    Object(obj) => {
      if obj.get("data") is Some(Array(entries)) {
        push_model_entries(models, entries)
      } else if obj.get("models") is Some(Array(entries)) {
        push_model_entries(models, entries)
      } else if obj.get("items") is Some(Array(entries)) {
        push_model_entries(models, entries)
      }
      if obj.get("models") is Some(Object(model_map)) {
        for key, entry in model_map {
          push_model_entry(models, entry, fallback_id=Some(key))
        }
      }
    }
    Array(entries) => push_model_entries(models, entries)
    _ => ()
  }
  sort_and_dedup_models(models)
}

///|
fn push_model_entries(
  models : Array[CodexModel],
  entries : Array[Json],
) -> Unit {
  for entry in entries {
    push_model_entry(models, entry, fallback_id=None)
  }
}

///|
fn push_model_entry(
  models : Array[CodexModel],
  entry : Json,
  fallback_id~ : String?,
) -> Unit {
  match entry {
    String(raw) => {
      let id = raw.trim().to_owned()
      if !id.is_empty() {
        models.push({ id, owned_by: "Codex" })
      }
    }
    Object(obj) => {
      let id = match string_field(obj, ["slug", "id", "model", "name"]) {
        Some(value) => Some(value)
        None => normalized_optional_string(fallback_id)
      }
      guard id is Some(id) else { return }
      let owned_by = string_field(obj, [
        "owned_by", "ownedBy", "provider", "vendor", "category", "owner",
      ]).unwrap_or("Codex")
      models.push({ id, owned_by })
    }
    _ =>
      match normalized_optional_string(fallback_id) {
        Some(id) => models.push({ id, owned_by: "Codex" })
        None => ()
      }
  }
}

///|
fn string_field(obj : Map[String, Json], keys : Array[String]) -> String? {
  for key in keys {
    if obj.get(key) is Some(String(value)) {
      let trimmed = value.trim().to_owned()
      if !trimmed.is_empty() {
        return Some(trimmed)
      }
    }
  }
  None
}

///|
fn normalized_optional_string(value : String?) -> String? {
  match value {
    Some(raw) => {
      let trimmed = raw.trim().to_owned()
      if trimmed.is_empty() {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

///|
fn sort_and_dedup_models(models : Array[CodexModel]) -> Array[CodexModel] {
  models.sort_by(fn(left, right) { ascii_lex_compare(left.id, right.id) })
  let deduped : Array[CodexModel] = []
  let mut previous : String? = None
  for model in models {
    if previous == Some(model.id) {
      ()
    } else {
      previous = Some(model.id)
      deduped.push(model)
    }
  }
  deduped
}

///|
fn ascii_lex_compare(left : String, right : String) -> Int {
  let limit = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i in 0..<limit {
    if left[i] < right[i] {
      return -1
    } else if left[i] > right[i] {
      return 1
    }
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}

///|
fn codex_models_response_json(models : Array[CodexModel]) -> Json {
  {
    "models": Json::array(models.map(fn(model) { model.to_moonstat_json() })),
    "object": Json::string("list"),
    "data": Json::array(models.map(fn(model) { model.to_openai_json() })),
  }.to_json()
}

///|
fn truncate_error_body(body : String) -> String {
  if body.length() <= 512 {
    body
  } else {
    body[:512].to_owned() + "..."
  }
}
