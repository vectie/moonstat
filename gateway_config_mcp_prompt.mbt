///|
async fn ConfigService::handle_get_claude_mcp_status(
  self : ConfigService,
  w : @httpx.ResponseWriter,
) -> Unit {
  write_usage_json(
    w,
    {
      "userConfigPath": Json::string(
        @pathx.join(moon_home_dir(), ".claude.json"),
      ),
      "userConfigExists": Json::boolean(
        @fsx.exists_as_file(@pathx.join(moon_home_dir(), ".claude.json")),
      ),
      "serverCount": Json::number(self.mcp_servers.length().to_double()),
    }.to_json(),
  )
}

///|
async fn ConfigService::handle_upsert_claude_mcp_server(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = proxy_json_body(r)
  match moon_mcp_server_from_request(r.path, body, "claude") {
    Some((id, server)) => {
      self.mcp_servers[id] = moon_mcp_server_with_app(server, "claude", true)
      write_usage_json(w, Json::boolean(true))
    }
    None => write_usage_json(w, Json::boolean(false))
  }
}

///|
async fn ConfigService::handle_delete_mcp_server(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = proxy_json_body(r)
  match proxy_string_request(r.path, body, ["id", "serverId", "server_id"]) {
    Some(id) => {
      let existed = self.mcp_servers.get(id) is Some(_)
      self.mcp_servers.remove(id)
      write_usage_json(w, Json::boolean(existed))
    }
    None => write_usage_json(w, Json::boolean(false))
  }
}

///|
async fn ConfigService::handle_validate_mcp_command(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  ignore(self)
  let body = proxy_json_body(r)
  let command = proxy_string_request(r.path, body, ["cmd", "command"]).unwrap_or(
    "",
  )
  write_usage_json(w, Json::boolean(moon_validate_mcp_command_name(command)))
}

///|
async fn ConfigService::handle_set_mcp_enabled(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = proxy_json_body(r)
  let app = moon_config_app_from_request(r.path, body).unwrap_or("claude")
  let enabled = proxy_bool_request(r.path, body, ["enabled"]).unwrap_or(true)
  match proxy_string_request(r.path, body, ["id", "serverId", "server_id"]) {
    Some(id) =>
      match self.mcp_servers.get(id) {
        Some(server) => {
          self.mcp_servers[id] = moon_mcp_server_with_app(server, app, enabled)
          write_usage_json(w, Json::boolean(true))
        }
        None => write_usage_json(w, Json::boolean(false))
      }
    None => write_usage_json(w, Json::boolean(false))
  }
}

///|
async fn ConfigService::handle_get_mcp_servers(
  self : ConfigService,
  w : @httpx.ResponseWriter,
) -> Unit {
  write_usage_json(w, moon_mcp_servers_object_for_app(self.mcp_servers, None))
}

///|
async fn ConfigService::handle_upsert_mcp_server(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = proxy_json_body(r)
  match moon_mcp_server_from_request(r.path, body, "claude") {
    Some((id, server)) => {
      self.mcp_servers[id] = server
      write_usage_json(w, Json::null())
    }
    None => write_usage_json(w, Json::null())
  }
}

///|
async fn ConfigService::handle_toggle_mcp_app(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = proxy_json_body(r)
  let app = moon_config_app_from_request(r.path, body).unwrap_or("claude")
  let enabled = proxy_bool_request(r.path, body, ["enabled"]).unwrap_or(true)
  match proxy_string_request(r.path, body, ["serverId", "server_id", "id"]) {
    Some(id) =>
      match self.mcp_servers.get(id) {
        Some(server) => {
          self.mcp_servers[id] = moon_mcp_server_with_app(server, app, enabled)
          write_usage_json(w, Json::null())
        }
        None => write_usage_json(w, Json::null())
      }
    None => write_usage_json(w, Json::null())
  }
}

///|
async fn ConfigService::handle_import_mcp_from_apps(
  self : ConfigService,
  w : @httpx.ResponseWriter,
) -> Unit {
  let imported = moon_import_mcp_from_apps_count(self.mcp_servers)
  write_usage_json(w, Json::number(imported.to_double()))
}

///|
async fn ConfigService::handle_get_prompts(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = proxy_json_body(r)
  let app = moon_config_app_from_request(r.path, body).unwrap_or("claude")
  write_usage_json(w, moon_prompts_object_for_app(self.prompts, app))
}

///|
async fn ConfigService::handle_upsert_prompt(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = proxy_json_body(r)
  match moon_prompt_from_request(r.path, body) {
    Some((app, id, prompt)) =>
      self.prompts[moon_prompt_store_key(app, id)] = prompt
    None => ()
  }
  write_usage_json(w, Json::null())
}

///|
async fn ConfigService::handle_delete_prompt(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = proxy_json_body(r)
  let app = moon_config_app_from_request(r.path, body).unwrap_or("claude")
  match proxy_string_request(r.path, body, ["id", "promptId", "prompt_id"]) {
    Some(id) => self.prompts.remove(moon_prompt_store_key(app, id))
    None => ()
  }
  write_usage_json(w, Json::null())
}

///|
async fn ConfigService::handle_enable_prompt(
  self : ConfigService,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = proxy_json_body(r)
  let app = moon_config_app_from_request(r.path, body).unwrap_or("claude")
  match proxy_string_request(r.path, body, ["id", "promptId", "prompt_id"]) {
    Some(id) =>
      match moon_prompt_file_path_from_request(r.path, body, app) {
        Ok(file_path) =>
          match moon_enable_prompt_json(self.prompts, app, id, file_path) {
            Ok(result) => write_usage_json(w, result)
            Err(error) => write_usage_bad_request(w, error)
          }
        Err(error) => write_usage_bad_request(w, error)
      }
    None => write_usage_json(w, Json::null())
  }
}
