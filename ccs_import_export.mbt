///|
const CCS_DB_BACKUP_DIR = "backups"

///|
fn ccs_suite_app_types() -> Array[String] {
  [
    "claude", "claude-desktop", "codex", "gemini", "opencode", "openclaw", "hermes",
  ]
}

///|
fn ccs_db_backup_dir() -> String {
  @pathx.join(ccs_app_config_dir(), CCS_DB_BACKUP_DIR)
}

///|
fn ccs_db_backup_path(filename : String) -> String {
  @pathx.join(ccs_db_backup_dir(), ccs_backup_filename(filename))
}

///|
fn ccs_backup_filename(filename : String) -> String {
  let sanitized = filename
    .replace(old="/", new="-")
    .replace(old="\\", new="-")
    .replace(old=":", new="-")
  if sanitized.has_suffix(".db") || sanitized.has_suffix(".json") {
    sanitized
  } else {
    sanitized + ".db"
  }
}

///|
async fn ccs_ensure_db_backup_dir() -> Unit {
  @fsx.make_directory(ccs_db_backup_dir(), recursive=true, exists_ok=true) catch {
    _ => ()
  }
}

///|
async fn Gateway::ccs_export_snapshot_json(self : Gateway) -> Json {
  {
    "format": Json::string("moonstat.config.v1"),
    "exportedAt": Json::number(@os.unix_seconds().to_double()),
    "settings": self.app_settings,
    "skills": ccs_skill_state_load(),
    "proxy": self.ccs_export_proxy_json(),
    "providers": self.ccs_export_providers_json(),
    "suite": moonstat_suite_manifest_json(host=self.host, port=self.port),
  }.to_json()
}

///|
fn Gateway::ccs_export_proxy_json(self : Gateway) -> Json {
  {
    "globalConfig": self.proxy_global_config_json(),
    "takeoverStatus": self.proxy_takeover_status_json(),
    "appConfigs": self.ccs_export_proxy_app_configs_json(),
    "defaultCostMultipliers": ccs_string_map_json(
      self.proxy_default_cost_multipliers,
    ),
    "pricingModelSources": ccs_string_map_json(self.proxy_pricing_model_sources),
    "upstreamProxyUrl": match self.upstream_proxy_url {
      Some(url) => Json::string(url)
      None => Json::null()
    },
  }.to_json()
}

///|
fn Gateway::ccs_export_proxy_app_configs_json(self : Gateway) -> Json {
  let obj : Map[String, Json] = Map([], capacity=0)
  for app in ccs_suite_app_types() {
    obj[app] = self.proxy_app_config_json(app)
  }
  Json::object(obj)
}

///|
fn Gateway::ccs_export_providers_json(self : Gateway) -> Json {
  let obj : Map[String, Json] = Map([], capacity=0)
  for app in ccs_suite_app_types() {
    obj[app] = self.provider_router.providers_ccs_json(app)
  }
  obj["universalProviders"] = self.provider_router.universal_providers_json()
  obj["routeStats"] = self.provider_router.route_stats_json()
  obj["circuitBreakerConfig"] = self.provider_router.circuit_config.to_json()
  Json::object(obj)
}

///|
fn ccs_string_map_json(map : Map[String, String]) -> Json {
  let obj : Map[String, Json] = Map([], capacity=0)
  for key in map.keys() {
    guard map.get(key) is Some(value) else { continue }
    obj[key] = Json::string(value)
  }
  Json::object(obj)
}

///|
async fn Gateway::ccs_export_config_to_file_json(
  self : Gateway,
  file_path : String,
) -> Json {
  let snapshot = self.ccs_export_snapshot_json()
  @fsx.write_to_file(file_path, snapshot.stringify(indent=2) + "\n") catch {
    error =>
      return {
        "success": Json::boolean(false),
        "message": Json::string("Export failed: \{error}"),
        "filePath": Json::string(file_path),
      }.to_json()
  }
  {
    "success": Json::boolean(true),
    "message": Json::string("SQL exported successfully"),
    "filePath": Json::string(file_path),
  }.to_json()
}

///|
async fn Gateway::ccs_import_config_from_file_json(
  self : Gateway,
  file_path : String,
) -> Json {
  let content = @fsx.read_file(file_path) catch {
    error =>
      return {
        "success": Json::boolean(false),
        "message": Json::string("Import failed: \{error}"),
        "filePath": Json::string(file_path),
      }.to_json()
  }
  let parsed = @json.parse(content) catch {
    error =>
      return {
        "success": Json::boolean(false),
        "message": Json::string("Import failed: \{error}"),
        "filePath": Json::string(file_path),
      }.to_json()
  }
  let backup_id = self.ccs_create_db_backup_json()
  self.ccs_apply_import_snapshot(parsed)
  {
    "success": Json::boolean(true),
    "message": Json::string("SQL imported successfully"),
    "filePath": Json::string(file_path),
    "backupId": backup_id,
    "warning": Json::null(),
  }.to_json()
}

///|
async fn Gateway::ccs_apply_import_snapshot(
  self : Gateway,
  snapshot : Json,
) -> Unit {
  guard snapshot is Object(obj) else { return }
  match obj.get("settings") {
    Some(settings) =>
      self.app_settings = ccs_merge_settings_for_save(
        settings,
        self.app_settings,
      )
    None => ()
  }
  match obj.get("skills") {
    Some(skills) => ignore(ccs_skill_state_save(skills))
    None => ()
  }
  match obj.get("proxy") {
    Some(Object(proxy)) => self.ccs_apply_import_proxy(proxy)
    _ => ()
  }
}

///|
fn Gateway::ccs_apply_import_proxy(
  self : Gateway,
  proxy : Map[String, Json],
) -> Unit {
  match proxy.get("globalConfig") {
    Some(Object(global)) => {
      match json_bool_from_map_any(global, ["proxyEnabled", "proxy_enabled"]) {
        Some(enabled) => self.proxy_enabled = enabled
        None => ()
      }
      match
        json_string_from_map_any(global, ["listenAddress", "listen_address"]) {
        Some(address) => self.proxy_listen_address = address
        None => ()
      }
      match ccs_json_int_from_map_any(global, ["listenPort", "listen_port"]) {
        Some(port) => self.proxy_listen_port = port
        None => ()
      }
      match
        json_bool_from_map_any(global, ["enableLogging", "enable_logging"]) {
        Some(enabled) => self.proxy_enable_logging = enabled
        None => ()
      }
    }
    _ => ()
  }
  match proxy.get("takeoverStatus") {
    Some(Object(takeover)) =>
      for app in ccs_suite_app_types() {
        match json_bool_from_map_any(takeover, [app]) {
          Some(enabled) => self.proxy_takeover_enabled.set(app, enabled)
          None => ()
        }
      }
    _ => ()
  }
}

///|
fn ccs_json_int_from_map_any(
  obj : Map[String, Json],
  keys : Array[String],
) -> Int? {
  for key in keys {
    match proxy_json_int(obj, key) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  None
}

///|
async fn Gateway::ccs_create_db_backup_json(self : Gateway) -> Json {
  ccs_ensure_db_backup_dir()
  let filename = ccs_new_backup_filename()
  let path = ccs_db_backup_path(filename)
  let snapshot = self.ccs_export_snapshot_json()
  @fsx.write_to_file(path, snapshot.stringify(indent=2) + "\n") catch {
    _ => return Json::string("")
  }
  Json::string(filename)
}

///|
fn ccs_new_backup_filename() -> String {
  let gen = @uuid.generator(@random.Rand::new())
  "moonstat-\{@os.unix_seconds()}-\{gen.v4()}.db"
}

///|
async fn ccs_list_db_backups_json() -> Json {
  let entries = @fsx.list_directory(ccs_db_backup_dir()) catch {
    _ => return Json::array([])
  }
  let rows : Array[Json] = []
  for entry in entries {
    if !(entry.kind is @fsx.FileKind::Regular) || !entry.name.has_suffix(".db") {
      continue
    }
    let content = @fsx.read_file(entry.path) catch { _ => "" }
    rows.push(
      {
        "filename": Json::string(entry.name),
        "sizeBytes": Json::number(content.length().to_double()),
        "createdAt": Json::string(ccs_file_mtime(entry.path).to_string()),
      }.to_json(),
    )
  }
  Json::array(rows)
}

///|
async fn Gateway::ccs_restore_db_backup_json(
  self : Gateway,
  filename : String,
) -> Json {
  let path = ccs_db_backup_path(filename)
  let content = @fsx.read_file(path) catch { _ => return Json::string("") }
  let parsed = @json.parse(content) catch { _ => return Json::string("") }
  self.ccs_apply_import_snapshot(parsed)
  Json::string(ccs_backup_filename(filename))
}

///|
async fn ccs_rename_db_backup_json(
  old_filename : String,
  new_name : String,
) -> Json {
  let old_path = ccs_db_backup_path(old_filename)
  let new_filename = ccs_backup_filename(new_name)
  let new_path = ccs_db_backup_path(new_filename)
  let content = @fsx.read_file(old_path) catch { _ => return Json::string("") }
  ccs_ensure_db_backup_dir()
  @fsx.write_to_file(new_path, content) catch {
    _ => return Json::string("")
  }
  @fsx.remove(old_path) catch {
    _ => ()
  }
  Json::string(new_filename)
}

///|
async fn ccs_delete_db_backup_json(filename : String) -> Json {
  @fsx.remove(ccs_db_backup_path(filename)) catch {
    _ => ()
  }
  Json::null()
}
