///|
pub struct Gateway {
  host : String
  port : Int
  model : String
  logger : @pino.Logger
  started_at_ms : Int
  /// Auth
  auth : AuthService
  /// Proxy routing and circuit breakers
  proxy : ProxyService
  /// Usage tracking and cost calculation
  usage : UsageService
  /// App configuration and settings
  config : ConfigService
  /// Session management
  session : SessionService
  /// Local workspace and file dialog operations
  workspace : WorkspaceService
  /// App runtime status and local tool lifecycle operations
  runtime : RuntimeService
  /// Skill discovery, installation, migration, and repository operations
  skills : SkillService
  /// OpenClaw and Hermes provider config
  openclaw : OpenClawService
}

///|
pub fn Gateway::new(
  port~ : Int,
  host? : String = "127.0.0.1",
  model? : String = "gpt-4o",
) -> Gateway {
  let logger = @pino.logger("moonstat", @pino.Transport::console())
  {
    host,
    port,
    model,
    logger,
    started_at_ms: @async.now().to_int(),
    auth: AuthService::new(),
    proxy: ProxyService::new(host, port),
    usage: UsageService::new(),
    config: ConfigService::new(),
    session: SessionService::new(),
    workspace: WorkspaceService::new(),
    runtime: RuntimeService::new(),
    skills: SkillService::new(),
    openclaw: OpenClawService::new(),
  }
}

///|
pub fn Gateway::host(self : Gateway) -> String {
  self.host
}

///|
pub fn Gateway::port(self : Gateway) -> Int {
  self.port
}

///|
fn moon_first_stream_event_ms(current : Int?, started_at_ms : Int?) -> Int? {
  match current {
    Some(_) => current
    None =>
      match started_at_ms {
        Some(started_at) => Some(max_int(@async.now().to_int() - started_at, 0))
        None => Some(0)
      }
  }
}

///|
fn ProviderRouteTarget::can_use_codex_compatible_upstream(
  self : ProviderRouteTarget,
) -> Bool {
  self.provider_type != Some("codex_oauth") &&
  self.base_url is Some(_) &&
  self.api_key is Some(_)
}

///|
fn ProviderRouteTarget::codex_uses_chat_completions(
  self : ProviderRouteTarget,
) -> Bool {
  if self.api_format == Some("openai_chat") {
    return true
  }
  match self.base_url {
    Some(base_url) => base_url.trim().has_suffix("/chat/completions")
    None => false
  }
}

///|
fn ProviderRouteTarget::can_use_claude_compatible_upstream(
  self : ProviderRouteTarget,
) -> Bool {
  self.provider_type != Some("codex_oauth") &&
  self.base_url is Some(_) &&
  self.api_key is Some(_)
}

///|
fn ProviderRouteTarget::claude_api_format(self : ProviderRouteTarget) -> String {
  if self.provider_type == Some("codex_oauth") {
    return "openai_responses"
  }
  match self.api_format {
    Some("openai_chat") => "openai_chat"
    Some("openai_responses") => "openai_responses"
    Some("gemini_native") => "gemini_native"
    _ => "anthropic"
  }
}

///|
fn ProviderRouteTarget::claude_api_format_for_model(
  self : ProviderRouteTarget,
  model : String,
) -> String {
  if !self.is_github_copilot_upstream() {
    return self.claude_api_format()
  }
  match self.copilot_model_vendor(model) {
    Some(vendor) if vendor.to_lower() == "openai" => "openai_responses"
    _ => "openai_chat"
  }
}

///|
fn ProviderRouteTarget::copilot_model_vendor(
  self : ProviderRouteTarget,
  model : String,
) -> String? {
  guard self.settings_config is Some(Object(settings)) else { return None }
  for
    key in [
      "copilotModels", "copilot_models", "modelCatalog", "model_catalog", "models",
    ] {
    match settings.get(key) {
      Some(models) =>
        match copilot_model_vendor_from_models_json(model, models) {
          Some(vendor) => return Some(vendor)
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
fn claude_api_format_needs_transform(api_format : String) -> Bool {
  api_format == "openai_chat" ||
  api_format == "openai_responses" ||
  api_format == "gemini_native"
}

///|
const MOONSTAT_PROXY_MANAGED_PLACEHOLDER = "PROXY_MANAGED"

///|
const HERMES_WEB_OFFLINE_ERROR = "hermes_web_offline"

///|
fn moon_is_managed_account_upstream_url(url : String) -> Bool {
  let (origin, path) = split_origin_and_path(url)
  let host = extract_host(origin).to_lower()
  host == "githubcopilot.com" ||
  host.has_suffix(".githubcopilot.com") ||
  (host == "chatgpt.com" && path.has_prefix("/backend-api/codex"))
}

///|
fn parse_custom_user_agent(value : String?) -> String? {
  match value {
    Some(raw) => {
      let trimmed = raw.trim().to_owned()
      if trimmed.is_empty() || !custom_user_agent_header_value_valid(trimmed) {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

///|
fn custom_user_agent_header_value_valid(value : String) -> Bool {
  for ch in value {
    let code = ch.to_int()
    if code == 9 {
      continue
    }
    if code < 32 || code == 127 {
      return false
    }
  }
  true
}

///|
fn moon_claude_code_beta_header(existing_beta : String?) -> String {
  let claude_code_beta = "claude-code-20250219"
  match existing_beta {
    Some(beta) if beta.contains(claude_code_beta) => beta
    Some(beta) if !beta.trim().is_empty() => "\{claude_code_beta},\{beta}"
    _ => claude_code_beta
  }
}

///|
fn codex_compatible_responses_endpoint(endpoint : String) -> String {
  let query = match endpoint.find("?") {
    Some(index) => endpoint[index:]
    None => ""
  }
  "/responses\{query}"
}

///|
fn codex_compatible_chat_completions_endpoint(endpoint : String) -> String {
  let query = match endpoint.find("?") {
    Some(index) => endpoint[index:]
    None => ""
  }
  "/chat/completions\{query}"
}

///|
fn claude_transform_endpoint(
  api_format : String,
  is_stream : Bool,
  request_path? : StringView = "/v1/messages",
) -> String {
  let request_path_only = match request_path.find("?") {
    Some(index) => request_path[:index]
    None => request_path
  }
  if !is_claude_messages_path(request_path_only) {
    return request_path.to_owned()
  }
  let query = claude_transform_passthrough_query(
    request_path, api_format, is_stream,
  )
  let target = match api_format {
    "openai_responses" => "/v1/responses"
    "openai_chat" => "/v1/chat/completions"
    "gemini_native" =>
      if is_stream {
        "/v1beta/models/__MODEL__:streamGenerateContent"
      } else {
        "/v1beta/models/__MODEL__:generateContent"
      }
    _ => "/v1/messages"
  }
  match query {
    Some(query) if !query.is_empty() => "\{target}?\{query}"
    _ => target
  }
}

///|
fn is_claude_messages_path(path : StringView) -> Bool {
  path == "/v1/messages"
}

///|
fn claude_transform_passthrough_query(
  request_path : StringView,
  api_format : String,
  is_stream : Bool,
) -> String? {
  match request_path.find("?") {
    Some(index) => {
      let path = request_path[:index]
      let query = request_path[index + 1:]
      let stripped = if is_claude_messages_path(path) {
        strip_claude_beta_query(query)
      } else {
        Some(query.to_owned())
      }
      gemini_stream_query_extra(api_format, is_stream, stripped)
    }
    None => gemini_stream_query_extra(api_format, is_stream, None)
  }
}

///|
fn strip_claude_beta_query(query : StringView) -> String? {
  let parts : Array[String] = []
  for pair in query.split("&") {
    if !pair.is_empty() && !pair.has_prefix("beta=") {
      parts.push(pair.to_owned())
    }
  }
  if parts.is_empty() {
    None
  } else {
    Some(parts.join("&"))
  }
}

///|
fn gemini_stream_query_extra(
  api_format : String,
  is_stream : Bool,
  query : String?,
) -> String? {
  if api_format != "gemini_native" {
    return query
  }
  let parts : Array[String] = []
  match query {
    Some(query) =>
      for pair in query.split("&") {
        if !pair.is_empty() && !pair.has_prefix("alt=") {
          parts.push(pair.to_owned())
        }
      }
    None => ()
  }
  if is_stream {
    parts.push("alt=sse")
  }
  Some(parts.join("&"))
}

///|
fn append_query_to_full_url(
  base_url : String,
  endpoint_trimmed : String,
) -> String {
  match endpoint_trimmed.find("?") {
    Some(index) => {
      let query = endpoint_trimmed[index + 1:]
      if query.is_empty() {
        base_url
      } else if base_url.contains("?") {
        "\{base_url}&\{query}"
      } else {
        "\{base_url}?\{query}"
      }
    }
    None => base_url
  }
}

///|
priv enum MoonClientFormat {
  Claude
  Codex
  OpenAI
  Gemini
  GeminiCli
  Unknown
} derive(Eq)

///|
fn MoonClientFormat::to_string(self : MoonClientFormat) -> String {
  match self {
    Claude => "claude"
    Codex => "codex"
    OpenAI => "openai"
    Gemini => "gemini"
    GeminiCli => "gemini_cli"
    Unknown => "unknown"
  }
}

///|
fn moon_client_format_from_path(path : String) -> MoonClientFormat {
  if path.contains("/v1/messages") {
    Claude
  } else if path.contains("/v1/responses") {
    Codex
  } else if path.contains("/v1/chat/completions") {
    OpenAI
  } else if path.contains("/v1internal/") && path.contains("generateContent") {
    GeminiCli
  } else if (path.contains("/v1beta/") || path.contains("/v1/")) &&
    path.contains("generateContent") {
    Gemini
  } else if path.contains("generateContent") {
    Gemini
  } else {
    Unknown
  }
}

///|
fn moon_client_format_from_body(body : Json) -> MoonClientFormat {
  guard body is Object(obj) else { return Unknown }
  if obj.get("messages") is Some(_) &&
    obj.get("model") is Some(_) &&
    obj.get("response_format") is None &&
    obj.get("contents") is None {
    if obj.get("max_tokens") is Some(_) {
      return Claude
    }
    return OpenAI
  }
  if obj.get("input") is Some(_) {
    return Codex
  }
  if obj.get("contents") is Some(_) {
    return Gemini
  }
  Unknown
}

///|
fn moon_client_format_for_request(
  path : String,
  body : Json?,
) -> MoonClientFormat {
  let format = moon_client_format_from_path(path)
  if format != Unknown {
    return format
  }
  match body {
    Some(body) => moon_client_format_from_body(body)
    None => Unknown
  }
}

///|
priv struct MoonClientSession {
  session_id : String
  client_provided : Bool
}

///|
fn MoonClientSession::upstream_session_id(self : MoonClientSession) -> String? {
  if self.client_provided {
    Some(self.session_id)
  } else {
    None
  }
}

///|
fn json_metadata_string(body : Json, key : String) -> String? {
  guard body is Object(obj) else { return None }
  guard obj.get("metadata") is Some(Object(metadata)) else { return None }
  match metadata.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_bool_field(json : Json, key : String) -> Bool? {
  guard json is Object(obj) else { return None }
  match obj.get(key) {
    Some(true) => Some(true)
    Some(false) => Some(false)
    _ => None
  }
}

///|
fn json_string_field(json : Json, key : String) -> String? {
  guard json is Object(obj) else { return None }
  match obj.get(key) {
    Some(String(value)) if !value.is_empty() => Some(value)
    _ => None
  }
}

///|
fn normalize_gemini_endpoint(path : StringView) -> String {
  let raw = path.to_owned()
  if raw.has_prefix("/gemini/v1beta/") {
    "/v1beta/\{raw["/gemini/v1beta/".length():]}"
  } else if raw.has_prefix("/gemini/v1/") {
    "/v1/\{raw["/gemini/v1/".length():]}"
  } else {
    raw
  }
}

///|
fn gemini_model_from_endpoint(endpoint : String) -> String {
  match endpoint.find("/models/") {
    Some(index) => {
      let rest = endpoint[index + "/models/".length():]
      let without_query = match rest.find("?") {
        Some(end) => rest[:end]
        None => rest
      }
      let model = match without_query.find(":") {
        Some(end) => without_query[:end].to_owned()
        None => without_query.to_owned()
      }
      if model.is_empty() {
        "unknown"
      } else {
        normalize_gemini_model_id(model)
      }
    }
    None => "unknown"
  }
}

///|
fn gemini_base_url() -> String {
  match getenv_or_none("GOOGLE_GEMINI_BASE_URL") {
    Some(url) if !url.is_empty() => url
    _ =>
      match getenv_or_none("GEMINI_BASE_URL") {
        Some(url) if !url.is_empty() => url
        _ => "https://generativelanguage.googleapis.com"
      }
  }
}

///|
fn gemini_base_is_full_url() -> Bool {
  env_bool("MOONSTAT_GEMINI_FULL_URL") || env_bool("GEMINI_FULL_URL")
}

///|
fn codex_base_is_full_url() -> Bool {
  env_bool("MOONSTAT_CODEX_FULL_URL") || env_bool("CODEX_FULL_URL")
}

///|
fn claude_base_is_full_url() -> Bool {
  env_bool("MOONSTAT_CLAUDE_FULL_URL") || env_bool("ANTHROPIC_FULL_URL")
}

///|
fn moon_model_mapping_from_env() -> ModelMapping? {
  let mapping = ModelMapping::new(
    haiku_model=env_first_non_empty([
      "MOONSTAT_ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    ]),
    sonnet_model=env_first_non_empty([
      "MOONSTAT_ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL",
    ]),
    opus_model=env_first_non_empty([
      "MOONSTAT_ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL",
    ]),
    default_model=env_first_non_empty([
      "MOONSTAT_ANTHROPIC_MODEL", "ANTHROPIC_MODEL",
    ]),
  )
  if mapping.has_mapping() {
    Some(mapping)
  } else {
    None
  }
}

///|
fn env_first_non_empty(keys : Array[String]) -> String? {
  for key in keys {
    match getenv_or_none(key) {
      Some(value) if !value.trim().is_empty() =>
        return Some(value.trim().to_owned())
      _ => continue
    }
  }
  None
}

///|
fn env_first_non_negative_decimal(keys : Array[String]) -> String? {
  for key in keys {
    match getenv_or_none(key) {
      Some(value) if usage_non_negative_decimal(value) =>
        return Some(value.trim().to_owned())
      _ => continue
    }
  }
  None
}

///|
fn url_contains_query_key(url : String) -> Bool {
  url.contains("?key=") || url.contains("&key=")
}

///|
fn env_bool(key : String) -> Bool {
  match getenv_or_none(key) {
    Some(value) => {
      let normalized = value.trim().to_lower()
      normalized == "1" ||
      normalized == "true" ||
      normalized == "yes" ||
      normalized == "on"
    }
    None => false
  }
}

///|
fn gemini_api_key() -> String? {
  match getenv_or_none("GEMINI_API_KEY") {
    Some(key) if !key.is_empty() => Some(key)
    _ =>
      match getenv_or_none("GOOGLE_API_KEY") {
        Some(key) if !key.is_empty() => Some(key)
        _ => None
      }
  }
}

///|
fn getenv_or_none(key : String) -> String? {
  @os.getenv(key) catch {
    _ => None
  }
}

///|
fn moon_normalize_app_type(app : String) -> String {
  match app.trim().to_lower() {
    "claude-desktop" | "claude_desktop" => "claude-desktop"
    "codex" => "codex"
    "gemini" => "gemini"
    "opencode" | "open-code" | "open_code" => "opencode"
    "openclaw" | "open-claw" | "open_claw" => "openclaw"
    "hermes" => "hermes"
    "omo" => "omo"
    "omo-slim" | "omo_slim" => "omo-slim"
    _ => "claude"
  }
}

///|
fn moon_home_dir() -> String {
  @os.home() catch {
    _ => "."
  }
}

///|
fn moon_ascii_digit_at(value : String, index : Int) -> Bool {
  let ch = value[index]
  ch >= '0' && ch <= '9'
}

///|
async fn moon_ensure_directory(path : String) -> Bool {
  @fsx.make_directory(path, recursive=true, exists_ok=true) catch {
    _ => return false
  }
  true
}

///|
async fn moon_open_directory_result_json(path : String) -> Result[Json, String] {
  if !moon_ensure_directory(path) {
    return Err("open_directory_create_failed")
  }
  Ok(Json::boolean(true))
}

///|
fn moon_preview(content : String, limit : Int) -> String {
  if content.length() <= limit {
    content
  } else {
    content[:limit].to_owned()
  }
}

///|
fn moon_count_case_insensitive_matches(
  haystack : String,
  needle : String,
) -> (Int, Int?) {
  let lower = haystack.to_lower()
  let query = needle.to_lower()
  if query.is_empty() {
    return (0, None)
  }
  let mut count = 0
  let mut first : Int? = None
  let mut offset = 0
  while offset <= lower.length() {
    match lower[offset:].find(query) {
      Some(found) => {
        let pos = offset + found
        if first is None {
          first = Some(pos)
        }
        count = count + 1
        offset = pos + query.length()
      }
      None => break
    }
  }
  (count, first)
}

///|
fn moon_preserve_secret_if_empty(
  incoming : Map[String, Json],
  existing : Map[String, Json],
  object_key : String,
  secret_key : String,
) -> Unit {
  guard incoming.get(object_key) is Some(Object(incoming_obj)) else { return }
  guard existing.get(object_key) is Some(Object(existing_obj)) else { return }
  let incoming_secret = json_string_from_map(incoming_obj, secret_key).unwrap_or(
    "",
  )
  let existing_secret = json_string_from_map(existing_obj, secret_key).unwrap_or(
    "",
  )
  if incoming_secret.is_empty() && !existing_secret.is_empty() {
    incoming_obj[secret_key] = Json::string(existing_secret)
    incoming[object_key] = Json::object(incoming_obj)
  }
}

///|
fn moon_optional_path_from_request(path : StringView, body : Json?) -> String? {
  match proxy_string_request(path, body, ["path", "appConfigDir"]) {
    Some(value) if !value.trim().is_empty() => return Some(value)
    Some(_) => return None
    None => ()
  }
  match body {
    Some(Object(obj)) =>
      match obj.get("path") {
        Some(Null) => None
        _ => None
      }
    _ => None
  }
}

///|
fn moon_json_primary_api_key_any(content : String) -> Bool {
  let parsed : Result[Json, Error] = moon_result(() => @json.parse(content))
  match parsed {
    Ok(Object(obj)) =>
      match json_string_from_map(obj, "primaryApiKey") {
        Some(value) => value == "any"
        None => false
      }
    _ => false
  }
}

///|
async fn moon_env_conflicts_json(app : String) -> Json {
  moon_env_conflicts_json_with_shell_files(app, moon_env_shell_config_paths())
}

///|
async fn moon_push_shell_env_conflicts(
  conflicts : Array[Json],
  file_path : String,
  keywords : Array[String],
) -> Unit {
  let content = @fsx.read_file(file_path) catch { _ => return }
  let mut line_number = 0
  for line_view in content.split("\n") {
    line_number += 1
    let trimmed = line_view.to_owned().trim().to_owned()
    guard moon_env_assignment_line(trimmed) is Some((var_name, var_value)) else {
      continue
    }
    if moon_env_name_matches_keywords(var_name, keywords) {
      conflicts.push(
        {
          "varName": Json::string(var_name),
          "varValue": Json::string(moon_trim_env_value_quotes(var_value)),
          "sourceType": Json::string("file"),
          "sourcePath": Json::string("\{file_path}:\{line_number}"),
        }.to_json(),
      )
    }
  }
}

///|
fn moon_env_conflict_keys(app : String) -> Array[String] {
  match app {
    "codex" =>
      ["OPENAI_API_KEY", "OPENAI_BASE_URL", "CODEX_HOME", "CODEX_AUTH_TOKEN"]
    "gemini" =>
      [
        "GEMINI_API_KEY", "GOOGLE_API_KEY", "GEMINI_BASE_URL", "GOOGLE_GEMINI_BASE_URL",
      ]
    "opencode" | "omo" | "omo-slim" =>
      [
        "OPENCODE_CONFIG_DIR", "OPENCODE_DB", "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
      ]
    "openclaw" =>
      [
        "OPENCLAW_CONFIG_DIR", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY",
      ]
    "hermes" =>
      [
        "HERMES_CONFIG_DIR", "HERMES_WEB_PORT", "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
      ]
    _ =>
      [
        "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", "CLAUDE_CONFIG_DIR", "CLAUDE_CODE_USE_BEDROCK",
      ]
  }
}

///|
async fn moon_delete_env_vars_json(body : Json?) -> Result[Json, String] {
  let backup = moon_env_backup_json(body)
  guard backup is Object(obj) else { return Err("invalid_backup") }
  guard obj.get("backupPath") is Some(String(backup_path)) else {
    return Err("missing_backup_path")
  }
  @fsx.make_directory(
    @pathx.dirname(backup_path),
    recursive=true,
    exists_ok=true,
  ) catch {
    error => return Err("创建备份目录失败: \{error}")
  }
  @fsx.write_to_file(backup_path, backup.stringify(indent=2) + "\n") catch {
    error => return Err("写入备份文件失败: \{error}")
  }
  for conflict in moon_env_conflicts_from_body(body) {
    match moon_delete_single_env_conflict(conflict) {
      Ok(_) => ()
      Err(error) =>
        return Err(
          "删除环境变量失败: \{error}. 备份已保存到: \{backup_path}",
        )
    }
  }
  Ok(backup)
}

///|
async fn moon_delete_single_env_conflict(
  conflict : Json,
) -> Result[Unit, String] {
  guard conflict is Object(obj) else { return Err("invalid_conflict") }
  let source_type = moon_env_conflict_string(obj, "sourceType", "source_type")
  let var_name = moon_env_conflict_string(obj, "varName", "var_name")
  let source_path = moon_env_conflict_string(obj, "sourcePath", "source_path")
  match (source_type, var_name, source_path) {
    (Some("file"), Some(var_name), Some(source_path)) => {
      let file_path = moon_env_source_file_path(source_path)
      guard !file_path.is_empty() else {
        return Err("无效的文件路径格式")
      }
      let content = @fsx.read_file(file_path) catch {
        error => return Err("读取文件失败 \{file_path}: \{error}")
      }
      let kept : Array[String] = []
      for line_view in content.split("\n") {
        let line = line_view.to_owned()
        match moon_env_assignment_line(line.trim().to_owned()) {
          Some((name, _)) if name == var_name => ()
          _ => kept.push(line)
        }
      }
      @fsx.write_to_file(file_path, kept.join("\n")) catch {
        error => return Err("写入文件失败 \{file_path}: \{error}")
      }
      Ok(())
    }
    (Some("system"), _, _) | (Some("process"), _, _) => Ok(())
    (Some(other), _, _) => Err("未知的环境变量来源类型: \{other}")
    _ => Err("invalid_conflict")
  }
}

///|
async fn moon_restore_single_env_conflict(
  conflict : Json,
) -> Result[Unit, String] {
  guard conflict is Object(obj) else { return Err("invalid_conflict") }
  let source_type = moon_env_conflict_string(obj, "sourceType", "source_type")
  let var_name = moon_env_conflict_string(obj, "varName", "var_name")
  let var_value = moon_env_conflict_string(obj, "varValue", "var_value")
  let source_path = moon_env_conflict_string(obj, "sourcePath", "source_path")
  match (source_type, var_name, var_value, source_path) {
    (Some("file"), Some(var_name), Some(var_value), Some(source_path)) => {
      let file_path = moon_env_source_file_path(source_path)
      guard !file_path.is_empty() else {
        return Err("无效的文件路径格式")
      }
      let content = @fsx.read_file(file_path) catch {
        error => return Err("读取文件失败 \{file_path}: \{error}")
      }
      @fsx.write_to_file(
        file_path,
        content + "\nexport \{var_name}=\{var_value}",
      ) catch {
        error => return Err("写入文件失败 \{file_path}: \{error}")
      }
      Ok(())
    }
    (Some(other), _, _, _) =>
      Err("无法恢复类型为 \{other} 的环境变量")
    _ => Err("invalid_conflict")
  }
}

///|
fn moon_env_conflicts_from_body(body : Json?) -> Array[Json] {
  match body {
    Some(Array(items)) => items
    Some(Object(obj)) =>
      match obj.get("conflicts") {
        Some(Array(items)) => items
        _ => []
      }
    _ => []
  }
}

///|
fn moon_env_conflict_string(
  obj : Map[String, Json],
  key : String,
  alt : String,
) -> String? {
  match obj.get(key) {
    Some(String(value)) => Some(value)
    _ =>
      match obj.get(alt) {
        Some(String(value)) => Some(value)
        _ => None
      }
  }
}

///|
fn moon_env_assignment_line(line : String) -> (String, String)? {
  if line.is_empty() || line.has_prefix("#") {
    return None
  }
  let export_line = if line.has_prefix("export ") {
    line[7:].to_owned().trim().to_owned()
  } else {
    line
  }
  match export_line.find("=") {
    Some(index) => {
      let name = export_line[:index].to_owned().trim().to_owned()
      let value = export_line[index + 1:].to_owned().trim().to_owned()
      if name.is_empty() {
        None
      } else {
        Some((name, value))
      }
    }
    None => None
  }
}

///|
fn moon_env_name_matches_keywords(
  var_name : String,
  keywords : Array[String],
) -> Bool {
  let upper = var_name.to_upper()
  for keyword in keywords {
    if upper.contains(keyword) {
      return true
    }
  }
  false
}

///|
fn moon_trim_env_value_quotes(value : String) -> String {
  let trimmed = value.trim().to_owned()
  if trimmed.length() >= 2 {
    if (trimmed.has_prefix("\"") && trimmed.has_suffix("\"")) ||
      (trimmed.has_prefix("'") && trimmed.has_suffix("'")) {
      return trimmed[1:trimmed.length() - 1].to_owned()
    }
  }
  trimmed
}

///|
fn moon_json_request(
  path : StringView,
  body : Json?,
  keys : Array[String],
) -> Json? {
  for key in keys {
    match usage_query_value(path, key) {
      Some(value) => return Some(moon_json_value_from_string(value))
      None => ()
    }
  }
  match body {
    Some(Object(obj)) =>
      for key in keys {
        match obj.get(key) {
          Some(value) => return Some(value)
          None => ()
        }
      }
    _ => ()
  }
  None
}

///|
fn moon_json_value_from_string(value : String) -> Json {
  try @json.parse(value) catch {
    _ => Json::string(value)
  } noraise {
    parsed => parsed
  }
}

///|
fn moon_mcp_apps_json(app : String, enabled? : Bool = true) -> Json {
  let apps = {
    "claude": Json::boolean(false),
    "claude-desktop": Json::boolean(false),
    "codex": Json::boolean(false),
    "gemini": Json::boolean(false),
    "opencode": Json::boolean(false),
    "openclaw": Json::boolean(false),
    "hermes": Json::boolean(false),
  }
  apps[moon_normalize_app_type(app)] = Json::boolean(enabled)
  Json::object(apps)
}

///|
fn moon_mcp_app_enabled(server : Json, app : String) -> Bool {
  guard server is Object(obj) else { return false }
  guard obj.get("apps") is Some(Object(apps)) else { return false }
  match apps.get(moon_normalize_app_type(app)) {
    Some(true) => true
    Some(false) => false
    _ => false
  }
}

///|
fn moon_mcp_server_with_app(
  server : Json,
  app : String,
  enabled : Bool,
) -> Json {
  let normalized = moon_normalize_app_type(app)
  match server {
    Object(obj) => {
      let next = obj
      let apps = match obj.get("apps") {
        Some(Object(existing)) => existing
        _ =>
          match moon_mcp_apps_json("claude", enabled=false) {
            Object(empty) => empty
            _ => {}
          }
      }
      apps[normalized] = Json::boolean(enabled)
      next["apps"] = Json::object(apps)
      Json::object(next)
    }
    _ => server
  }
}

///|
fn moon_mcp_server_from_request(
  path : StringView,
  body : Json?,
  default_app : String,
) -> (String, Json)? {
  match moon_json_request(path, body, ["server"]) {
    Some(Object(server)) =>
      match json_string_from_map_any(server, ["id", "serverId", "server_id"]) {
        Some(id) =>
          return Some(
            (
              id,
              moon_mcp_normalize_server(id, Json::object(server), default_app),
            ),
          )
        None => ()
      }
    _ => ()
  }
  guard proxy_string_request(path, body, ["id", "serverId", "server_id"])
    is Some(id) else {
    return None
  }
  let spec = moon_json_request(path, body, ["spec", "server"]).unwrap_or(
    Json::object({}),
  )
  Some((id, moon_mcp_server_from_spec(id, spec, default_app)))
}

///|
fn moon_mcp_server_from_spec(id : String, spec : Json, app : String) -> Json {
  let name = match spec {
    Object(obj) => json_string_from_map_any(obj, ["name"]).unwrap_or(id)
    _ => id
  }
  Json::object({
    "id": Json::string(id),
    "name": Json::string(name),
    "server": spec,
    "apps": moon_mcp_apps_json(app),
    "description": Json::null(),
    "homepage": Json::null(),
    "docs": Json::null(),
    "tags": Json::array([]),
  })
}

///|
fn moon_mcp_normalize_server(
  id : String,
  server : Json,
  default_app : String,
) -> Json {
  match server {
    Object(obj) => {
      let next = obj
      if next.get("id") is None {
        next["id"] = Json::string(id)
      }
      if next.get("name") is None {
        next["name"] = Json::string(id)
      }
      if next.get("server") is None {
        next["server"] = Json::object({})
      }
      if next.get("apps") is None {
        next["apps"] = moon_mcp_apps_json(default_app)
      }
      if next.get("tags") is None {
        next["tags"] = Json::array([])
      }
      Json::object(next)
    }
    _ => moon_mcp_server_from_spec(id, Json::object({}), default_app)
  }
}

///|
fn moon_mcp_servers_object_for_app(
  servers : Map[String, Json],
  app : String?,
) -> Json {
  let result : Map[String, Json] = {}
  for id in servers.keys() {
    guard servers.get(id) is Some(server) else { continue }
    match app {
      Some(app_type) =>
        if moon_mcp_app_enabled(server, app_type) {
          result[id] = server
        }
      None => result[id] = server
    }
  }
  Json::object(result)
}

///|
fn moon_mcp_valid_server_spec(spec : Json) -> Bool {
  guard spec is Object(obj) else { return false }
  let typ = json_string_from_map_any(obj, ["type"]).unwrap_or("stdio")
  match typ {
    "stdio" =>
      json_string_from_map_any(obj, ["command"]).unwrap_or("").trim() != ""
    "http" | "sse" =>
      json_string_from_map_any(obj, ["url"]).unwrap_or("").trim() != ""
    _ => false
  }
}

///|
fn moon_mcp_import_spec_for_app(app : String, spec : Json) -> Json {
  let normalized = moon_normalize_app_type(app)
  if normalized != "gemini" {
    return spec
  }
  match spec {
    Object(obj) => {
      let next = obj
      match next.get("httpUrl") {
        Some(http_url) => {
          next.remove("httpUrl")
          next["url"] = http_url
          next["type"] = Json::string("http")
        }
        None => ()
      }
      if next.get("type") is None {
        if next.get("command") is Some(_) {
          next["type"] = Json::string("stdio")
        } else if next.get("url") is Some(_) {
          next["type"] = Json::string("sse")
        }
      }
      Json::object(next)
    }
    _ => spec
  }
}

///|
fn moon_import_mcp_servers_map(
  servers : Map[String, Json],
  app : String,
  mcp_servers : Map[String, Json],
) -> Int {
  let mut changed = 0
  for id in mcp_servers.keys() {
    guard mcp_servers.get(id) is Some(spec) else { continue }
    let import_spec = moon_mcp_import_spec_for_app(app, spec)
    if !moon_mcp_valid_server_spec(import_spec) {
      continue
    }
    match servers.get(id) {
      Some(existing) =>
        if !moon_mcp_app_enabled(existing, app) {
          servers[id] = moon_mcp_server_with_app(existing, app, true)
          changed += 1
        }
      None => {
        servers[id] = moon_mcp_server_from_spec(id, import_spec, app)
        changed += 1
      }
    }
  }
  changed
}

///|
fn moon_import_mcp_from_root_json(
  servers : Map[String, Json],
  app : String,
  root : Json,
) -> Int {
  guard root is Object(obj) else { return 0 }
  guard obj.get("mcpServers") is Some(Object(mcp_servers)) else { return 0 }
  moon_import_mcp_servers_map(servers, app, mcp_servers)
}

///|
fn moon_import_mcp_from_codex_toml_text(
  servers : Map[String, Json],
  content : String,
) -> Int {
  let raw_specs : Map[String, Json] = {}
  let mut current_id : String? = None
  let mut current_table = ""
  for line_view in content.split("\n") {
    let line = moon_toml_strip_comment(line_view.to_owned()).trim().to_owned()
    if line.is_empty() {
      continue
    }
    if line.has_prefix("[") && line.has_suffix("]") {
      let section = line[1:line.length() - 1].trim().to_owned()
      match moon_codex_mcp_section(section) {
        Some((id, table)) => {
          current_id = Some(id)
          current_table = table
          if raw_specs.get(id) is None {
            raw_specs[id] = Json::object({})
          }
        }
        None => {
          current_id = None
          current_table = ""
        }
      }
      continue
    }
    guard current_id is Some(id) else { continue }
    guard moon_toml_assignment(line) is Some((key, raw_value)) else { continue }
    let spec = moon_codex_raw_mcp_spec(raw_specs, id)
    if current_table.is_empty() {
      match moon_toml_value(raw_value) {
        Some(value) => spec[key] = value
        None => ()
      }
    } else {
      let nested_key = if current_table == "http_headers" {
        "headers"
      } else {
        current_table
      }
      let nested = match spec.get(nested_key) {
        Some(Object(obj)) => obj
        _ => {
          let obj : Map[String, Json] = {}
          spec[nested_key] = Json::object(obj)
          obj
        }
      }
      match moon_toml_value(raw_value) {
        Some(String(value)) => nested[key] = Json::string(value)
        _ => ()
      }
    }
    raw_specs[id] = Json::object(spec)
  }
  let normalized : Map[String, Json] = {}
  for id in raw_specs.keys() {
    guard raw_specs.get(id) is Some(raw_spec) else { continue }
    normalized[id] = moon_codex_mcp_unified_spec(raw_spec)
  }
  moon_import_mcp_servers_map(servers, "codex", normalized)
}

///|
fn moon_codex_raw_mcp_spec(
  specs : Map[String, Json],
  id : String,
) -> Map[String, Json] {
  match specs.get(id) {
    Some(Object(obj)) => obj
    _ => {
      let obj : Map[String, Json] = {}
      specs[id] = Json::object(obj)
      obj
    }
  }
}

///|
fn moon_codex_mcp_section(section : String) -> (String, String)? {
  let rest = if section.has_prefix("mcp_servers.") {
    section["mcp_servers.".length():].to_owned()
  } else if section.has_prefix("mcp.servers.") {
    section["mcp.servers.".length():].to_owned()
  } else {
    return None
  }
  let parts = rest.split(".").collect()
  if parts.length() == 0 {
    return None
  }
  let id = parts[0].trim().to_owned()
  if id.is_empty() {
    return None
  }
  let table = if parts.length() > 1 { parts[1].trim().to_owned() } else { "" }
  match table {
    "" | "env" | "http_headers" | "headers" => Some((id, table))
    _ => None
  }
}

///|
fn moon_codex_mcp_unified_spec(raw_spec : Json) -> Json {
  guard raw_spec is Object(raw) else { return Json::object({}) }
  let typ = json_string_from_map_any(raw, ["type"]).unwrap_or("stdio")
  let spec : Map[String, Json] = { "type": Json::string(typ) }
  match typ {
    "stdio" => {
      match raw.get("command") {
        Some(String(command)) => spec["command"] = Json::string(command)
        _ => ()
      }
      match raw.get("args") {
        Some(Array(args)) => spec["args"] = Json::array(args)
        _ => ()
      }
      match raw.get("cwd") {
        Some(String(cwd)) if !cwd.trim().is_empty() =>
          spec["cwd"] = Json::string(cwd)
        _ => ()
      }
      match raw.get("env") {
        Some(Object(env)) => spec["env"] = Json::object(env)
        _ => ()
      }
    }
    "http" | "sse" => {
      match raw.get("url") {
        Some(String(url)) => spec["url"] = Json::string(url)
        _ => ()
      }
      match raw.get("http_headers") {
        Some(Object(headers)) => spec["headers"] = Json::object(headers)
        _ =>
          match raw.get("headers") {
            Some(Object(headers)) => spec["headers"] = Json::object(headers)
            _ => ()
          }
      }
    }
    _ => ()
  }
  for key in raw.keys() {
    if moon_codex_mcp_core_field(typ, key) {
      continue
    }
    guard raw.get(key) is Some(value) else { continue }
    spec[key] = value
  }
  Json::object(spec)
}

///|
fn moon_codex_mcp_core_field(typ : String, key : String) -> Bool {
  match typ {
    "stdio" =>
      key == "type" ||
      key == "command" ||
      key == "args" ||
      key == "env" ||
      key == "cwd"
    "http" | "sse" =>
      key == "type" || key == "url" || key == "http_headers" || key == "headers"
    _ => key == "type"
  }
}

///|
fn moon_toml_strip_comment(line : String) -> String {
  let mut in_quote = false
  let mut quote = 0
  let mut escaped = false
  for i in 0..<line.length() {
    let ch = line[i]
    if in_quote {
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch.to_int() == quote {
        in_quote = false
      }
    } else if ch == '"' || ch == '\'' {
      in_quote = true
      quote = ch.to_int()
    } else if ch == '#' {
      return line[:i].to_owned()
    }
  }
  line
}

///|
fn moon_toml_assignment(line : String) -> (String, String)? {
  guard line.find("=") is Some(index) else { return None }
  let key = line[:index].trim().to_owned()
  let value = line[index + 1:].trim().to_owned()
  if key.is_empty() {
    None
  } else {
    Some((key, value))
  }
}

///|
fn moon_toml_value(raw : String) -> Json? {
  let value = raw.trim().to_owned()
  if value.is_empty() {
    return None
  }
  if value.has_prefix("[") && value.has_suffix("]") {
    let items : Array[Json] = []
    for item in moon_toml_split_csv(value[1:value.length() - 1].to_owned()) {
      match moon_toml_value(item) {
        Some(String(text)) => items.push(Json::string(text))
        Some(true) => items.push(Json::boolean(true))
        Some(false) => items.push(Json::boolean(false))
        Some(Number(number, ..)) => items.push(Json::number(number))
        _ => ()
      }
    }
    return Some(Json::array(items))
  }
  if value.has_prefix("{") && value.has_suffix("}") {
    let obj : Map[String, Json] = {}
    for item in moon_toml_split_csv(value[1:value.length() - 1].to_owned()) {
      match moon_toml_assignment(item) {
        Some((key, nested_raw)) =>
          match moon_toml_value(nested_raw) {
            Some(String(text)) => obj[key] = Json::string(text)
            _ => ()
          }
        None => ()
      }
    }
    return Some(Json::object(obj))
  }
  if (value.has_prefix("\"") && value.has_suffix("\"")) ||
    (value.has_prefix("'") && value.has_suffix("'")) {
    return Some(Json::string(value[1:value.length() - 1].to_owned()))
  }
  match value {
    "true" => Some(Json::boolean(true))
    "false" => Some(Json::boolean(false))
    _ =>
      try @string.parse_int(value, base=10) catch {
        _ => Some(Json::string(value))
      } noraise {
        parsed => Some(Json::number(parsed.to_double()))
      }
  }
}

///|
fn moon_toml_split_csv(text : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let mut in_quote = false
  let mut quote = 0
  let mut escaped = false
  for i in 0..<text.length() {
    let ch = text[i]
    if in_quote {
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch.to_int() == quote {
        in_quote = false
      }
    } else if ch == '"' || ch == '\'' {
      in_quote = true
      quote = ch.to_int()
    } else if ch == ',' {
      let item = text[start:i].trim().to_owned()
      if !item.is_empty() {
        parts.push(item)
      }
      start = i + 1
    }
  }
  let tail = text[start:].trim().to_owned()
  if !tail.is_empty() {
    parts.push(tail)
  }
  parts
}

///|
fn moon_clean_blank_lines(lines : Array[String]) -> String {
  let cleaned : Array[String] = []
  let mut blank_run = 0
  for line in lines {
    if line.trim().is_empty() {
      blank_run += 1
      if blank_run <= 1 {
        cleaned.push("")
      }
    } else {
      blank_run = 0
      cleaned.push(line)
    }
  }
  cleaned.join("\n")
}

///|
async fn moon_import_mcp_from_apps_count(servers : Map[String, Json]) -> Int {
  let mut total = 0
  total += moon_import_mcp_from_file(
    servers,
    "claude",
    @pathx.join(moon_home_dir(), ".claude.json"),
  )
  total += moon_import_mcp_from_codex_file(
    servers,
    moon_config_file_path("codex"),
  )
  total += moon_import_mcp_from_file(
    servers,
    "gemini",
    @pathx.join(moon_config_dir("gemini"), "settings.json"),
  )
  total
}

///|
fn moon_validate_mcp_command_name(command : String) -> Bool {
  let trimmed = command.trim()
  !trimmed.is_empty() &&
  !trimmed.contains("/") &&
  !trimmed.contains("\\") &&
  !trimmed.contains("\u{0000}")
}

///|
fn moon_prompt_store_key(app : String, id : String) -> String {
  "\{moon_normalize_app_type(app)}:\{id}"
}

///|
fn moon_prompt_from_request(
  path : StringView,
  body : Json?,
) -> (String, String, Json)? {
  let app = moon_config_app_from_request(path, body).unwrap_or("claude")
  match moon_json_request(path, body, ["prompt"]) {
    Some(Object(prompt)) =>
      match json_string_from_map_any(prompt, ["id"]) {
        Some(id) =>
          return Some(
            (app, id, moon_normalize_prompt(id, Json::object(prompt))),
          )
        None => ()
      }
    _ => ()
  }
  guard proxy_string_request(path, body, ["id", "promptId", "prompt_id"])
    is Some(id) else {
    return None
  }
  let name = proxy_string_request(path, body, ["name"]).unwrap_or(id)
  let content = proxy_string_request(path, body, ["content"]).unwrap_or("")
  let description = proxy_string_request(path, body, ["description"])
  let enabled = proxy_bool_request(path, body, ["enabled"]).unwrap_or(true)
  let now = Json::string(@async.now().to_string())
  let prompt : Map[String, Json] = {
    "id": Json::string(id),
    "name": Json::string(name),
    "content": Json::string(content),
    "enabled": Json::boolean(enabled),
    "createdAt": now,
    "updatedAt": now,
  }
  match description {
    Some(value) => prompt["description"] = Json::string(value)
    None => ()
  }
  Some((app, id, Json::object(prompt)))
}

///|
async fn moon_enable_prompt_json(
  prompts : Map[String, Json],
  app : String,
  id : String,
  file_path : String,
) -> Result[Json, String] {
  let normalized = moon_normalize_app_type(app)
  let prefix = "\{normalized}:"
  let mut selected_content = ""
  let mut found = false
  for key in prompts.keys() {
    if !key.has_prefix(prefix) {
      continue
    }
    guard prompts.get(key) is Some(Object(prompt)) else { continue }
    guard json_string_from_map_any(prompt, ["id"]) is Some(prompt_id) else {
      continue
    }
    if prompt_id == id {
      selected_content = json_string_from_map_any(prompt, ["content"]).unwrap_or(
        "",
      )
      found = true
      break
    }
  }
  if !found {
    return Err("提示词 \{id} 不存在")
  }
  @fsx.make_directory(@pathx.dirname(file_path), recursive=true, exists_ok=true) catch {
    error => return Err("创建提示词目录失败: \{error}")
  }
  @fsx.write_to_file(file_path, selected_content) catch {
    error => return Err("写入提示词文件失败: \{error}")
  }
  let now = Json::string(@async.now().to_string())
  for key in prompts.keys() {
    if !key.has_prefix(prefix) {
      continue
    }
    guard prompts.get(key) is Some(Object(prompt)) else { continue }
    let next = prompt
    let enabled = match json_string_from_map_any(next, ["id"]) {
      Some(prompt_id) => prompt_id == id
      None => false
    }
    next["enabled"] = Json::boolean(enabled)
    if enabled {
      next["updatedAt"] = now
    }
    prompts[key] = Json::object(next)
  }
  Ok(Json::null())
}

///|
fn moon_normalize_prompt(id : String, prompt : Json) -> Json {
  match prompt {
    Object(obj) => {
      let next = obj
      if next.get("id") is None {
        next["id"] = Json::string(id)
      }
      if next.get("name") is None {
        next["name"] = Json::string(id)
      }
      if next.get("content") is None {
        next["content"] = Json::string("")
      }
      if next.get("enabled") is None {
        next["enabled"] = Json::boolean(true)
      }
      let now = Json::string(@async.now().to_string())
      if next.get("createdAt") is None {
        next["createdAt"] = now
      }
      next["updatedAt"] = now
      Json::object(next)
    }
    _ => Json::object({})
  }
}

///|
fn moon_prompts_object_for_app(
  prompts : Map[String, Json],
  app : String,
) -> Json {
  let normalized = moon_normalize_app_type(app)
  let prefix = "\{normalized}:"
  let result : Map[String, Json] = {}
  for key in prompts.keys() {
    if key.has_prefix(prefix) {
      guard prompts.get(key) is Some(Object(prompt)) else { continue }
      match json_string_from_map_any(prompt, ["id"]) {
        Some(id) => result[id] = Json::object(prompt)
        None => ()
      }
    }
  }
  Json::object(result)
}

///|
fn gemini_request_is_stream(endpoint : String, body : Json) -> Bool {
  moon_streaming_request(endpoint, body, {})
}

///|
fn moon_streaming_request(
  endpoint : String,
  body : Json,
  headers : Map[String, String],
) -> Bool {
  if json_bool_field(body, "stream").unwrap_or(false) {
    return true
  }
  if endpoint.contains("streamGenerateContent") || endpoint.contains("alt=sse") {
    return true
  }
  match headers.get("accept") {
    Some(accept) => accept.contains("text/event-stream")
    None => false
  }
}

///|
fn moon_unit_success_json() -> Json {
  Json::null()
}

///|
fn moon_update_tray_menu_result() -> Json {
  Json::boolean(false)
}

///|
priv struct ProxyProviderQuery {
  provider_id : String
  app_type : String
}

///|
fn json_non_empty_string_from_map_any(
  obj : Map[String, Json],
  keys : Array[String],
) -> String? {
  for key in keys {
    match json_string_from_map(obj, key) {
      Some(value) if !value.trim().is_empty() => return Some(value)
      _ => ()
    }
  }
  None
}

///|
fn codex_toml_string_value(content : String, key : String) -> String? {
  for raw_line in content.split("\n") {
    let line = raw_line.trim()
    if line.has_prefix("#") {
      continue
    }
    let mut index = 0
    let mut found_key = ""
    let mut found_value = ""
    for part in line.split("=") {
      if index == 0 {
        found_key = part.trim().to_owned()
      } else if index == 1 {
        found_value = part.trim().to_owned()
      }
      index += 1
    }
    if index < 2 || found_key != key {
      continue
    }
    let value = found_value
    if value.length() >= 2 &&
      value[0] == '"' &&
      value[value.length() - 1] == '"' {
      return Some(value[1:value.length() - 1].to_owned())
    }
    if !value.is_empty() {
      return Some(value)
    }
  }
  None
}

///|
fn suite_write_outcome_json() -> Json {
  let empty : Map[String, Json] = {}
  Json::object(empty)
}

///|
fn suite_object_payload(body : Json?, key : String) -> Json? {
  match body {
    Some(Object(obj)) =>
      match obj.get(key) {
        Some(Object(nested)) => Some(Json::object(nested))
        Some(_) => None
        None => Some(Json::object(obj))
      }
    _ => None
  }
}

///|
fn suite_object_request(path : StringView, body : Json?, key : String) -> Json? {
  match suite_object_payload(body, key) {
    Some(payload) => return Some(payload)
    None => ()
  }
  match usage_query_value(path, key) {
    Some(raw) => {
      let parsed = @json.parse(raw) catch { _ => return None }
      match parsed {
        Object(obj) => Some(Json::object(obj))
        _ => None
      }
    }
    None => None
  }
}

///|
fn split_csv_json(value : String) -> Json {
  let items : Array[Json] = []
  for raw in value.split(",") {
    let trimmed = raw.trim().to_owned()
    if !trimmed.is_empty() {
      items.push(Json::string(trimmed))
    }
  }
  Json::array(items)
}

///|
const HERMES_DASHBOARD_COMMAND = "hermes dashboard"

///|
const HERMES_DASHBOARD_LOG_PATH = "/tmp/moonstat_hermes_dashboard.log"

///|
fn normalize_claude_desktop_mode(mode : String) -> String? {
  match mode.trim().to_lower() {
    "direct" => Some("direct")
    "proxy" => Some("proxy")
    _ => None
  }
}

///|
fn split_endpoint_urls(value : String) -> Array[String] {
  let urls : Array[String] = []
  for raw in value.split(",") {
    urls.push(raw.to_owned())
  }
  urls
}

///|
const MOONSTAT_ENDPOINT_DEFAULT_TIMEOUT_SECS = 8

///|
const MOONSTAT_ENDPOINT_MIN_TIMEOUT_SECS = 2

///|
const MOONSTAT_ENDPOINT_MAX_TIMEOUT_SECS = 30

///|
fn moon_endpoint_invalid_url_error(url : String) -> String {
  if url.has_prefix("http://") || url.has_prefix("https://") {
    if moon_endpoint_url_missing_host(url) {
      "URL 无效: empty host"
    } else {
      "URL 无效"
    }
  } else {
    "URL 无效: relative URL without a base"
  }
}

///|
fn moon_endpoint_url_missing_host(url : String) -> Bool {
  match endpoint_url_host_start(url) {
    Some(start) => {
      if url.length() <= start {
        return true
      }
      let rest = url[start:]
      rest.has_prefix("/") || rest.has_prefix("?") || rest.has_prefix("#")
    }
    None => false
  }
}

///|
fn endpoint_url_host_start(url : String) -> Int? {
  if url.has_prefix("http://") {
    Some(7)
  } else if url.has_prefix("https://") {
    Some(8)
  } else {
    None
  }
}

///|
fn parse_bool_value(value : String) -> Bool? {
  match value.trim().to_owned().to_lower() {
    "true" | "1" | "yes" | "on" => Some(true)
    "false" | "0" | "no" | "off" => Some(false)
    _ => None
  }
}

///|
fn parse_non_negative_decimal_to_double(value : String) -> Double? {
  let trimmed = value.trim().to_owned()
  if trimmed.is_empty() {
    return None
  }
  let mut seen_dot = false
  let mut seen_digit = false
  for ch in trimmed {
    if ch == '.' {
      if seen_dot {
        return None
      }
      seen_dot = true
    } else {
      let code = ch.to_int()
      if code < '0'.to_int() || code > '9'.to_int() {
        return None
      }
      seen_digit = true
    }
  }
  if !seen_digit {
    return None
  }
  Some(parse_decimal_scaled(trimmed, 1_000_000L).to_double() / 1_000_000.0)
}

///|
fn claude_desktop_model_list_json(
  provider? : ProviderRouteTarget? = None,
) -> Json {
  let routes = match provider {
    Some(provider) => provider.resolved_claude_desktop_model_routes()
    None => []
  }
  if !routes.is_empty() {
    return claude_desktop_route_model_list_json(routes)
  }
  let data = [
    claude_desktop_model_json("claude-sonnet-4-6", supports_1m=true),
    claude_desktop_model_json("claude-opus-4-8", supports_1m=true),
    claude_desktop_model_json("claude-haiku-4-5", supports_1m=true),
  ]
  {
    "data": Json::array(data),
    "has_more": Json::boolean(false),
    "first_id": Json::string("claude-sonnet-4-6"),
    "last_id": Json::string("claude-haiku-4-5"),
  }.to_json()
}

///|
fn claude_desktop_route_model_list_json(
  routes : Array[(String, String, String?, Bool)],
) -> Json {
  let data = routes.map(fn(route) {
    let (route_id, _, label_override, supports_1m) = route
    claude_desktop_model_json(route_id, label_override~, supports_1m~)
  })
  let first_id = match routes.get(0) {
    Some((route_id, _, _, _)) => Json::string(route_id)
    None => Json::null()
  }
  let last_id = if routes.is_empty() {
    Json::null()
  } else {
    match routes.get(routes.length() - 1) {
      Some((route_id, _, _, _)) => Json::string(route_id)
      None => Json::null()
    }
  }
  {
    "data": Json::array(data),
    "has_more": Json::boolean(false),
    "first_id": first_id,
    "last_id": last_id,
  }.to_json()
}

///|
fn claude_desktop_model_json(
  id : String,
  label_override? : String? = None,
  supports_1m? : Bool = true,
) -> Json {
  let obj : Map[String, Json] = {
    "type": Json::string("model"),
    "id": Json::string(id),
    "created_at": Json::string("2024-01-01T00:00:00Z"),
  }
  match label_override {
    Some(label) => obj["labelOverride"] = Json::string(label)
    None => ()
  }
  if supports_1m {
    obj["supports1m"] = Json::boolean(true)
  }
  Json::object(obj)
}

///|
fn normalize_claude_desktop_request_model(
  request : AnthropicRequest,
  app_type : String,
) -> AnthropicRequest {
  if app_type != "claude-desktop" {
    return request
  }
  let model = normalize_claude_desktop_model_id(request.model)
  if model == request.model {
    request
  } else {
    {
      model,
      max_tokens: request.max_tokens,
      messages: request.messages,
      system: request.system,
      tools: request.tools,
      stream: request.stream,
    }
  }
}

///|
fn normalize_claude_desktop_model_id(model : String) -> String {
  let trimmed = model.trim().to_owned()
  let route_id = strip_one_m_suffix_for_route_lookup(trimmed)
  if !is_claude_safe_model_id(route_id) {
    return model.trim().to_owned()
  }
  match claude_role_keyword(route_id) {
    Some("opus") => "claude-opus-4-8"
    Some("haiku") => "claude-haiku-4-5"
    Some("sonnet") => "claude-sonnet-4-6"
    _ => route_id
  }
}

///|
fn strip_one_m_suffix_for_route_lookup(model : String) -> String {
  let trimmed = model.trim().to_owned()
  let marker = "[1m]"
  if trimmed.to_lower().has_suffix(marker) {
    trimmed[:trimmed.length() - marker.length()].trim().to_owned()
  } else {
    trimmed
  }
}

///|
fn is_claude_safe_model_id(model : String) -> Bool {
  let normalized = model.trim().to_lower()
  if normalized.contains("[1m]") {
    return false
  }
  let tail = if normalized.has_prefix("anthropic/claude-") {
    normalized["anthropic/claude-".length():]
  } else if normalized.has_prefix("claude-") {
    normalized["claude-".length():]
  } else {
    return false
  }
  ["sonnet-", "opus-", "haiku-"].any(prefix => {
    tail.has_prefix(prefix) && tail.length() > prefix.length()
  })
}

///|
fn claude_role_keyword(model : String) -> String? {
  let normalized = model.to_lower()
  if normalized.contains("opus") {
    Some("opus")
  } else if normalized.contains("haiku") {
    Some("haiku")
  } else if normalized.contains("sonnet") {
    Some("sonnet")
  } else {
    None
  }
}

///|
fn ProviderRouteTarget::resolved_claude_desktop_model_routes(
  self : ProviderRouteTarget,
) -> Array[(String, String, String?, Bool)] {
  let routes : Array[(String, String, String?, Bool)] = []
  if self.claude_desktop_model_routes.is_empty() {
    return routes
  }
  let reserved_route_ids : Array[String] = []
  for route_id in self.claude_desktop_model_routes.keys() {
    let trimmed = route_id.trim().to_owned()
    if is_claude_safe_model_id(trimmed) {
      reserved_route_ids.push(trimmed)
    }
  }
  let route_ids : Array[String] = []
  for route_id in self.claude_desktop_model_routes.keys() {
    route_ids.push(route_id)
  }
  route_ids.sort()
  for route_id in route_ids {
    let trimmed_route_id = route_id.trim().to_owned()
    guard self.claude_desktop_model_routes.get(route_id) is Some(route) else {
      continue
    }
    let upstream_model = route.model.trim().to_owned()
    if trimmed_route_id.is_empty() || upstream_model.is_empty() {
      continue
    }
    let route_id_is_safe = is_claude_safe_model_id(trimmed_route_id)
    let resolved_route_id = if route_id_is_safe {
      trimmed_route_id
    } else {
      next_claude_desktop_catalog_safe_route_id(routes, reserved_route_ids)
    }
    let label_override = match route.label_override {
      Some(label) => {
        let label = label.trim().to_owned()
        if label.is_empty() {
          None
        } else {
          Some(label)
        }
      }
      None => if route_id_is_safe { None } else { Some(upstream_model) }
    }
    routes.push(
      (
        resolved_route_id,
        upstream_model,
        label_override,
        route.supports_1m.unwrap_or(false),
      ),
    )
  }
  routes.sort_by(fn(left, right) {
    let (left_route_id, _, _, _) = left
    let (right_route_id, _, _, _) = right
    left_route_id.compare(right_route_id)
  })
  let deduped : Array[(String, String, String?, Bool)] = []
  for route in routes {
    let (route_id, _, _, _) = route
    match deduped.last() {
      Some((previous_route_id, _, _, _)) if previous_route_id == route_id => ()
      _ => deduped.push(route)
    }
  }
  deduped
}

///|
fn next_claude_desktop_catalog_safe_route_id(
  existing : Array[(String, String, String?, Bool)],
  reserved : Array[String],
) -> String {
  for route_id in claude_desktop_default_proxy_route_ids() {
    if !reserved.contains(route_id) &&
      !existing.any(fn(route) {
        let (existing_route_id, _, _, _) = route
        existing_route_id == route_id
      }) {
      return route_id
    }
  }
  for index in 2..<10000 {
    let route_id = "claude-sonnet-4-6-r\{index}"
    if !reserved.contains(route_id) &&
      !existing.any(fn(route) {
        let (existing_route_id, _, _, _) = route
        existing_route_id == route_id
      }) {
      return route_id
    }
  }
  "claude-sonnet-4-6-r10000"
}

///|
fn ProviderRouteTarget::claude_desktop_route_upstream_model(
  self : ProviderRouteTarget,
  request_model : String,
) -> String? {
  let requested = strip_one_m_suffix_for_route_lookup(request_model)
  if requested.is_empty() || self.claude_desktop_model_routes.is_empty() {
    return None
  }
  let routes = self.resolved_claude_desktop_model_routes()
  for route in routes {
    let (route_id, upstream_model, _, _) = route
    if route_id == requested {
      return Some(upstream_model)
    }
  }
  for route in routes {
    let (route_id, upstream_model, _, _) = route
    if claude_desktop_opus_route_alias_matches(route_id, requested) {
      return Some(upstream_model)
    }
  }
  guard is_claude_safe_model_id(requested) else { return None }
  guard claude_role_keyword(requested) is Some(role) else { return None }
  for route in routes {
    let (route_id, upstream_model, _, _) = route
    if claude_role_keyword(route_id) == Some(role) {
      return Some(upstream_model)
    }
  }
  None
}

///|
fn claude_desktop_opus_route_alias_matches(
  route_id : String,
  requested : String,
) -> Bool {
  let route = strip_one_m_suffix_for_route_lookup(route_id).trim().to_lower()
  let requested = requested.trim().to_lower()
  (route == "claude-opus-4-7" && requested == "claude-opus-4-8") ||
  (route == "claude-opus-4-8" && requested == "claude-opus-4-7")
}
