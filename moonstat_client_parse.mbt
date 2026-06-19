///|
pub fn moonstat_models_from_json(
  json : Json,
) -> Result[Array[MoonstatModel], String] {
  let rows = match json {
    Object(obj) =>
      match obj.get("models") {
        Some(Array(models)) => models
        Some(Object(models)) => models.values().to_array()
        Some(_) => return Err("moonstat models field is not an array or object")
        None =>
          match obj.get("data") {
            Some(Array(models)) => models
            Some(_) => return Err("moonstat data field is not an array")
            None => return Err("moonstat models response has no models")
          }
      }
    Array(models) => models
    _ => return Err("moonstat models response is not an object or array")
  }
  let parsed : Array[MoonstatModel] = []
  for row in rows {
    match MoonstatModel::from_json(row) {
      Ok(model) => parsed.push(model)
      Err(err) => return Err(err)
    }
  }
  Ok(parsed)
}

///|
pub fn MoonstatModel::from_json(json : Json) -> Result[MoonstatModel, String] {
  let obj = match json {
    Object(obj) => obj
    _ => return Err("moonstat model entry is not an object")
  }
  let id = match moonstat_json_string_field(obj, "id") {
    Some(value) => value
    None =>
      match moonstat_json_string_field(obj, "slug") {
        Some(value) => value
        None =>
          match moonstat_json_string_field(obj, "name") {
            Some(value) => value
            None => return Err("moonstat model entry has no id")
          }
      }
  }
  Ok({
    id,
    owner: moonstat_json_string_field(obj, "owned_by"),
    context_window: moonstat_json_int_field(obj, "context_window"),
  })
}

///|
pub fn MoonstatUsageSummary::from_json(
  json : Json,
) -> Result[MoonstatUsageSummary, String] {
  let obj = match json {
    Object(obj) => obj
    _ => return Err("moonstat usage summary is not an object")
  }
  Ok({
    total_requests: moonstat_json_int_field(obj, "totalRequests").unwrap_or(0),
    total_cost: moonstat_json_string_field(obj, "totalCost").unwrap_or("0"),
    total_input_tokens: moonstat_json_int64_field(obj, "totalInputTokens").unwrap_or(
      0L,
    ),
    total_output_tokens: moonstat_json_int64_field(obj, "totalOutputTokens").unwrap_or(
      0L,
    ),
    total_cache_creation_tokens: moonstat_json_int64_field(
      obj, "totalCacheCreationTokens",
    ).unwrap_or(0L),
    total_cache_read_tokens: moonstat_json_int64_field(
      obj, "totalCacheReadTokens",
    ).unwrap_or(0L),
    real_total_tokens: moonstat_json_int64_field(obj, "realTotalTokens").unwrap_or(
      0L,
    ),
    success_rate: moonstat_json_double_field(obj, "successRate").unwrap_or(0.0),
    cache_hit_rate: moonstat_json_double_field(obj, "cacheHitRate").unwrap_or(
      0.0,
    ),
  })
}

///|
pub fn moonstat_agent_clients_from_suite_status(
  status : Json,
) -> Result[Array[MoonstatAgentClient], String] {
  let obj = match status {
    Object(obj) if moonstat_suite_status_contract_valid(obj) => obj
    _ => return Err("moonstat suite status contract is invalid")
  }
  match obj.get("manifest") {
    Some(Object(manifest)) if moonstat_suite_manifest_contract_valid(manifest) =>
      moonstat_agent_clients_from_manifest(Json::object(manifest))
    _ => Err("moonstat suite status has no valid manifest")
  }
}

///|
pub fn moonstat_agent_clients_from_manifest(
  manifest : Json,
) -> Result[Array[MoonstatAgentClient], String] {
  let obj = match manifest {
    Object(obj) if moonstat_suite_manifest_contract_valid(obj) => obj
    _ => return Err("moonstat suite manifest contract is invalid")
  }
  let rows = match obj.get("agentClients") {
    Some(Array(rows)) => rows
    Some(_) => return Err("moonstat agentClients field is not an array")
    None => return Err("moonstat suite manifest has no agentClients")
  }
  let clients : Array[MoonstatAgentClient] = []
  for row in rows {
    match MoonstatAgentClient::from_json(row) {
      Ok(client) => clients.push(client)
      Err(err) => return Err(err)
    }
  }
  Ok(clients)
}

///|
pub fn MoonstatAgentClient::from_json(
  json : Json,
) -> Result[MoonstatAgentClient, String] {
  let obj = match json {
    Object(obj) => obj
    _ => return Err("moonstat agent client entry is not an object")
  }
  let id = match moonstat_json_string_field(obj, "id") {
    Some(value) => value
    None => return Err("moonstat agent client entry has no id")
  }
  let app_type = match moonstat_json_string_field(obj, "appType") {
    Some(value) => value
    None => return Err("moonstat agent client entry has no appType")
  }
  let protocol = match moonstat_json_string_field(obj, "protocol") {
    Some(value) => value
    None => return Err("moonstat agent client entry has no protocol")
  }
  let base_url = match moonstat_json_string_field(obj, "baseUrl") {
    Some(value) => moonstat_client_normalize_base_url(value)
    None => return Err("moonstat agent client entry has no baseUrl")
  }
  let primary_route = match moonstat_json_string_field(obj, "primaryRoute") {
    Some(value) => value
    None => return Err("moonstat agent client entry has no primaryRoute")
  }
  Ok({
    id,
    app_type,
    protocol,
    base_url,
    primary_route,
    setup_command: moonstat_json_string_field(obj, "setupCommand"),
    usage: moonstat_json_string_field(obj, "usage"),
  })
}

///|
fn moonstat_json_string_field(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) if !value.trim().is_empty() => Some(value)
    _ => None
  }
}

///|
fn moonstat_json_double_field(obj : Map[String, Json], key : String) -> Double? {
  match obj.get(key) {
    Some(Number(value, ..)) => Some(value)
    _ => None
  }
}

///|
fn moonstat_json_int_field(obj : Map[String, Json], key : String) -> Int? {
  match moonstat_json_double_field(obj, key) {
    Some(value) => Some(value.trunc().to_int())
    None => None
  }
}

///|
fn moonstat_json_int64_field(obj : Map[String, Json], key : String) -> Int64? {
  match moonstat_json_double_field(obj, key) {
    Some(value) => Some(value.trunc().to_int64())
    None => None
  }
}

///|
pub fn moonstat_base_url_from_suite_status(status : Json) -> String? {
  match status {
    Object(obj) if moonstat_suite_status_contract_valid(obj) =>
      moonstat_base_url_from_suite_status_object(obj)
    _ => None
  }
}

///|
fn moonstat_suite_status_contract_valid(obj : Map[String, Json]) -> Bool {
  moonstat_json_string_field(obj, "contract") == Some(@suite.status_contract()) &&
  moonstat_json_string_field(obj, "service") == Some(@suite.service_name())
}

///|
fn moonstat_base_url_from_suite_status_object(
  obj : Map[String, Json],
) -> String? {
  match obj.get("manifest") {
    Some(Object(manifest)) if moonstat_suite_manifest_contract_valid(manifest) =>
      moonstat_base_url_from_json_object(manifest)
    _ => None
  }
}

///|
fn moonstat_suite_manifest_contract_valid(obj : Map[String, Json]) -> Bool {
  moonstat_json_string_field(obj, "contract") ==
  Some(@suite.manifest_contract()) &&
  moonstat_json_string_field(obj, "service") == Some(@suite.service_name())
}

///|
fn moonstat_base_url_from_json_object(obj : Map[String, Json]) -> String? {
  match obj.get("baseUrl") {
    Some(String(url)) if !url.trim().is_empty() =>
      Some(moonstat_client_normalize_base_url(url))
    _ => None
  }
}
