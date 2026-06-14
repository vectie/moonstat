///|
priv struct CcsSessionMeta {
  provider_id : String
  session_id : String
  title : String?
  summary : String?
  project_dir : String?
  created_at : Int64?
  last_active_at : Int64?
  source_path : String?
  resume_command : String?
}

///|
priv struct CcsSessionMessage {
  role : String
  content : String
  ts : Int64?
}

///|
priv struct CcsDeleteSessionRequest {
  provider_id : String
  session_id : String
  source_path : String
}

///|
priv struct CcsDeleteSessionOutcome {
  provider_id : String
  session_id : String
  source_path : String
  success : Bool
  error : String?
}

///|
priv struct CcsSessionTerminalLaunch {
  program : String
  args : Array[String]
}

///|
let ccs_session_title_max_chars : Int = 80

///|
let ccs_session_read_cap : Int = 256 * 1024

///|
async fn ccs_list_sessions_json() -> Json {
  let sessions = ccs_scan_sessions()
  ccs_sort_sessions_desc(sessions)
  Json::array(sessions.map(fn(session) { session.to_json() }))
}

///|
async fn ccs_get_session_messages_json(
  provider_id : String,
  source_path : String,
) -> Result[Json, String] {
  match ccs_load_session_messages(provider_id, source_path) {
    Ok(messages) => Ok(Json::array(messages.map(message => message.to_json())))
    Err(error) => Err(error)
  }
}

///|
async fn ccs_delete_session_json(
  provider_id : String,
  session_id : String,
  source_path : String,
) -> Result[Json, String] {
  match ccs_delete_session(provider_id, session_id, source_path) {
    Ok(deleted) => Ok(Json::boolean(deleted))
    Err(error) => Err(error)
  }
}

///|
async fn ccs_delete_sessions_json(
  items : Array[CcsDeleteSessionRequest],
) -> Json {
  let outcomes = []
  for item in items {
    let outcome = match
      ccs_delete_session(item.provider_id, item.session_id, item.source_path) {
      Ok(true) =>
        CcsDeleteSessionOutcome::{
          provider_id: item.provider_id,
          session_id: item.session_id,
          source_path: item.source_path,
          success: true,
          error: None,
        }
      Ok(false) =>
        CcsDeleteSessionOutcome::{
          provider_id: item.provider_id,
          session_id: item.session_id,
          source_path: item.source_path,
          success: false,
          error: Some("Session was not deleted"),
        }
      Err(error) =>
        CcsDeleteSessionOutcome::{
          provider_id: item.provider_id,
          session_id: item.session_id,
          source_path: item.source_path,
          success: false,
          error: Some(error),
        }
    }
    outcomes.push(outcome.to_json())
  }
  Json::array(outcomes)
}

///|
fn ccs_delete_session_requests_from_json(
  value : Json?,
) -> Array[CcsDeleteSessionRequest]? {
  let raw_items = match value {
    Some(Array(items)) => Some(items)
    Some(Object(obj)) =>
      match obj.get("items") {
        Some(Array(items)) => Some(items)
        _ => None
      }
    _ => None
  }
  guard raw_items is Some(raw_items) else { return None }
  let items = []
  for raw in raw_items {
    match ccs_delete_session_request_from_json(raw) {
      Some(item) => items.push(item)
      None => return None
    }
  }
  Some(items)
}

///|
async fn ccs_launch_session_terminal_json(
  command : String,
  cwd : String?,
  custom_config : String?,
  preferred_terminal : String?,
) -> Result[Json, String] {
  if command.trim().is_empty() {
    return Err("Resume command is empty")
  }
  let target = ccs_session_terminal_target(preferred_terminal)
  let launch = match
    ccs_session_terminal_launch(target, command, cwd, custom_config) {
    Ok(launch) => launch
    Err(error) => return Err(error)
  }
  let result = @spawn.spawn(
    launch.program,
    launch.args.map(arg => arg[:]),
    timeout=5000,
  ) catch {
    err => return Err("Failed to launch terminal: \{err}")
  }
  if result.status == 0 {
    Ok(Json::boolean(true))
  } else {
    let detail = if result.stderr.trim().is_empty() {
      result.stdout.trim()
    } else {
      result.stderr.trim()
    }
    Err(
      if detail.is_empty() {
        "Terminal command execution failed"
      } else {
        detail.to_owned()
      },
    )
  }
}

///|
fn CcsSessionMeta::to_json(self : CcsSessionMeta) -> Json {
  let obj : Map[String, Json] = {
    "providerId": Json::string(self.provider_id),
    "sessionId": Json::string(self.session_id),
  }
  match self.title {
    Some(value) => obj["title"] = Json::string(value)
    None => ()
  }
  match self.summary {
    Some(value) => obj["summary"] = Json::string(value)
    None => ()
  }
  match self.project_dir {
    Some(value) => obj["projectDir"] = Json::string(value)
    None => ()
  }
  match self.created_at {
    Some(value) => obj["createdAt"] = Json::number(value.to_double())
    None => ()
  }
  match self.last_active_at {
    Some(value) => obj["lastActiveAt"] = Json::number(value.to_double())
    None => ()
  }
  match self.source_path {
    Some(value) => obj["sourcePath"] = Json::string(value)
    None => ()
  }
  match self.resume_command {
    Some(value) => obj["resumeCommand"] = Json::string(value)
    None => ()
  }
  Json::object(obj)
}

///|
fn CcsSessionMessage::to_json(self : CcsSessionMessage) -> Json {
  let obj : Map[String, Json] = {
    "role": Json::string(self.role),
    "content": Json::string(self.content),
  }
  match self.ts {
    Some(value) => obj["ts"] = Json::number(value.to_double())
    None => ()
  }
  Json::object(obj)
}

///|
fn CcsDeleteSessionOutcome::to_json(self : CcsDeleteSessionOutcome) -> Json {
  let obj : Map[String, Json] = {
    "providerId": Json::string(self.provider_id),
    "sessionId": Json::string(self.session_id),
    "sourcePath": Json::string(self.source_path),
    "success": Json::boolean(self.success),
  }
  match self.error {
    Some(value) => obj["error"] = Json::string(value)
    None => ()
  }
  Json::object(obj)
}

///|
fn ccs_delete_session_request_from_json(
  value : Json,
) -> CcsDeleteSessionRequest? {
  guard value is Object(obj) else { return None }
  guard json_string_from_map_any(obj, ["providerId", "provider_id"])
    is Some(provider_id) else {
    return None
  }
  guard json_string_from_map_any(obj, ["sessionId", "session_id"])
    is Some(session_id) else {
    return None
  }
  guard json_string_from_map_any(obj, ["sourcePath", "source_path"])
    is Some(source_path) else {
    return None
  }
  Some(CcsDeleteSessionRequest::{ provider_id, session_id, source_path })
}

///|
fn ccs_session_terminal_target(preferred : String?) -> String {
  match preferred {
    Some(value) => {
      let target = value.trim().to_lower()
      match target {
        "" => "terminal"
        "iterm2" => "iterm"
        _ => target.to_owned()
      }
    }
    None => "terminal"
  }
}

///|
fn ccs_session_terminal_from_settings(settings : Json) -> String? {
  match settings {
    Object(obj) =>
      match
        json_string_from_map_any(obj, [
          "preferredTerminal", "preferred_terminal",
        ]) {
        Some(value) if !value.trim().is_empty() => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
async fn ccs_session_terminal_launch(
  target : String,
  command : String,
  cwd : String?,
  custom_config : String?,
) -> Result[CcsSessionTerminalLaunch, String] {
  match target {
    "terminal" => Ok(ccs_session_terminal_app_launch(command, cwd))
    "iterm" | "iTerm" => Ok(ccs_session_iterm_launch(command, cwd))
    "ghostty" => Ok(ccs_session_ghostty_launch(command, cwd))
    "kitty" => Ok(ccs_session_kitty_launch(command, cwd))
    "wezterm" => Ok(ccs_session_wezterm_like_launch("WezTerm", command, cwd))
    "kaku" => Ok(ccs_session_wezterm_like_launch("Kaku", command, cwd))
    "alacritty" => Ok(ccs_session_alacritty_launch(command, cwd))
    "custom" => ccs_session_custom_launch(command, cwd, custom_config)
    "warp" => ccs_session_warp_launch(command, cwd)
    _ => Err("Unsupported terminal target: \{target}")
  }
}

///|
async fn ccs_session_warp_launch(
  command : String,
  cwd : String?,
) -> Result[CcsSessionTerminalLaunch, String] {
  guard cwd is Some(dir) && !dir.trim().is_empty() else {
    return Err("Failed to resume session without cwd")
  }
  guard @fsx.exists(dir) else {
    return Err(
      "Failed to create temporary script file for launching Warp: cwd not found: \{dir}",
    )
  }
  let gen = @uuid.generator(@random.Rand::new())
  let script_path = @pathx.join(dir, ".moonstat-warp-\{gen.v4()}.sh")
  let script = [
    "#!/usr/bin/env sh",
    "",
    "rm -- \"$0\"",
    "",
    "exec \{command}",
    "",
  ].join("\n")
  @fsx.write_to_file(script_path, script, create=0o755) catch {
    error =>
      return Err("Failed to write to temporary script file for Warp: \{error}")
  }
  Ok(CcsSessionTerminalLaunch::{
    program: "open",
    args: [
      "-a",
      "Warp",
      "warp://action/new_tab?path=\{ccs_session_url_query_encode(script_path)}",
    ],
  })
}

///|
fn ccs_session_terminal_app_launch(
  command : String,
  cwd : String?,
) -> CcsSessionTerminalLaunch {
  let full_command = ccs_session_shell_command(command, cwd)
  let escaped = ccs_session_escape_osascript(full_command)
  let script = [
    "tell application \"Terminal\"",
    "    activate",
    "    do script \"\{escaped}\"",
    "end tell",
  ].join("\n")
  CcsSessionTerminalLaunch::{ program: "osascript", args: ["-e", script] }
}

///|
fn ccs_session_iterm_launch(
  command : String,
  cwd : String?,
) -> CcsSessionTerminalLaunch {
  let full_command = ccs_session_shell_command(command, cwd)
  let escaped = ccs_session_escape_osascript(full_command)
  let script = [
    "tell application \"iTerm\"",
    "    activate",
    "    create window with default profile",
    "    tell current session of current window",
    "        write text \"\{escaped}\"",
    "    end tell",
    "end tell",
  ].join("\n")
  CcsSessionTerminalLaunch::{ program: "osascript", args: ["-e", script] }
}

///|
fn ccs_session_ghostty_launch(
  command : String,
  cwd : String?,
) -> CcsSessionTerminalLaunch {
  let args : Array[String] = [
    "-na", "Ghostty", "--args", "--quit-after-last-window-closed=true",
  ]
  match cwd {
    Some(dir) if !dir.trim().is_empty() =>
      args.push("--working-directory=\{dir}")
    _ => ()
  }
  args.push("-e")
  args.push(ccs_session_shell())
  args.push("-l")
  args.push("-c")
  args.push(command)
  CcsSessionTerminalLaunch::{ program: "open", args }
}

///|
fn ccs_session_kitty_launch(
  command : String,
  cwd : String?,
) -> CcsSessionTerminalLaunch {
  CcsSessionTerminalLaunch::{
    program: "open",
    args: [
      "-na",
      "kitty",
      "--args",
      "-e",
      ccs_session_shell(),
      "-l",
      "-c",
      ccs_session_shell_command(command, cwd),
    ],
  }
}

///|
fn ccs_session_wezterm_like_launch(
  app_name : String,
  command : String,
  cwd : String?,
) -> CcsSessionTerminalLaunch {
  let args : Array[String] = ["-na", app_name, "--args", "start"]
  match cwd {
    Some(dir) if !dir.trim().is_empty() => {
      args.push("--cwd")
      args.push(dir)
    }
    _ => ()
  }
  args.push("--")
  args.push(ccs_session_shell())
  args.push("-c")
  args.push(ccs_session_shell_command(command, None))
  CcsSessionTerminalLaunch::{ program: "open", args }
}

///|
fn ccs_session_alacritty_launch(
  command : String,
  cwd : String?,
) -> CcsSessionTerminalLaunch {
  let args : Array[String] = ["-na", "Alacritty", "--args"]
  match cwd {
    Some(dir) if !dir.trim().is_empty() => {
      args.push("--working-directory")
      args.push(dir)
    }
    _ => ()
  }
  args.push("-e")
  args.push(ccs_session_shell())
  args.push("-c")
  args.push(ccs_session_shell_command(command, None))
  CcsSessionTerminalLaunch::{ program: "open", args }
}

///|
fn ccs_session_custom_launch(
  command : String,
  cwd : String?,
  custom_config : String?,
) -> Result[CcsSessionTerminalLaunch, String] {
  guard custom_config is Some(template) else {
    return Err("No custom terminal config provided")
  }
  if template.trim().is_empty() {
    return Err("Custom terminal command template is empty")
  }
  let dir = cwd.unwrap_or(".")
  let final_command = template
    .replace_all(old="{command}", new=command)
    .replace_all(old="{cwd}", new=dir)
  Ok(CcsSessionTerminalLaunch::{ program: "sh", args: ["-c", final_command] })
}

///|
fn ccs_session_shell_command(command : String, cwd : String?) -> String {
  match cwd {
    Some(dir) if !dir.trim().is_empty() =>
      "cd \{ccs_session_shell_escape(dir)} && \{command}"
    _ => command
  }
}

///|
fn ccs_session_shell_escape(value : String) -> String {
  "\"" +
  value.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"") +
  "\""
}

///|
fn ccs_session_escape_osascript(value : String) -> String {
  value.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"")
}

///|
fn ccs_session_url_query_encode(value : String) -> String {
  let builder = StringBuilder::new()
  for ch in value {
    match ch {
      'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' =>
        builder.write_char(ch)
      _ => {
        let bytes = @encoding/utf8.encode(ch.to_string())
        for byte in bytes {
          let hex = byte.to_int()
          builder.write_char('%')
          builder.write_char(ccs_session_hex_digit((hex >> 4) & 0xF))
          builder.write_char(ccs_session_hex_digit(hex & 0xF))
        }
      }
    }
  }
  builder.to_string()
}

///|
fn ccs_session_hex_digit(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).unsafe_to_char()
  } else {
    ('A'.to_int() + n - 10).unsafe_to_char()
  }
}

///|
fn ccs_session_shell() -> String {
  let shell = @os.getenv("SHELL") catch { _ => None }
  match shell {
    Some(value) if !value.trim().is_empty() => value
    _ => "/bin/zsh"
  }
}

///|
async fn ccs_scan_sessions() -> Array[CcsSessionMeta] {
  let result = []
  for path in ccs_collect_provider_session_files("codex") {
    match ccs_parse_codex_session(path) {
      Some(meta) => result.push(meta)
      None => ()
    }
  }
  for path in ccs_collect_provider_session_files("claude") {
    match ccs_parse_claude_session(path) {
      Some(meta) => result.push(meta)
      None => ()
    }
  }
  for path in ccs_collect_provider_session_files("gemini") {
    match ccs_parse_gemini_session(path) {
      Some(meta) => result.push(meta)
      None => ()
    }
  }
  result.append(ccs_scan_opencode_sessions())
  for path in ccs_collect_provider_session_files("openclaw") {
    match ccs_parse_generic_json_session(path, "openclaw") {
      Some(meta) => result.push(meta)
      None => ()
    }
  }
  result.append(ccs_scan_hermes_sessions())
  result
}

///|
fn ccs_sort_sessions_desc(sessions : Array[CcsSessionMeta]) -> Unit {
  sessions.sort_by(fn(left, right) {
    let left_key = ccs_session_sort_key(left)
    let right_key = ccs_session_sort_key(right)
    if left_key == right_key {
      right.session_id.compare(left.session_id)
    } else if left_key < right_key {
      1
    } else {
      -1
    }
  })
}

///|
fn ccs_session_sort_key(session : CcsSessionMeta) -> Int64 {
  match session.last_active_at {
    Some(value) => value
    None =>
      match session.created_at {
        Some(value) => value
        None => 0L
      }
  }
}

///|
async fn ccs_load_session_messages(
  provider_id : String,
  source_path : String,
) -> Result[Array[CcsSessionMessage], String] {
  let provider = ccs_normalize_app_type(provider_id)
  if source_path.has_prefix("sqlite:") {
    return match provider {
      "opencode" => ccs_load_opencode_sqlite_messages(source_path)
      "hermes" => ccs_load_hermes_sqlite_messages(source_path)
      _ => Err("Unsupported SQLite session provider: \{provider_id}")
    }
  }
  guard @fsx.exists_as_file(source_path) else {
    return Err("session source not found: \{source_path}")
  }
  let content = ccs_read_session_file_text(source_path) catch {
    error => return Err("Failed to open session file: \{error}")
  }
  match provider {
    "codex" => Ok(ccs_load_codex_messages(content))
    "claude" => Ok(ccs_load_claude_messages(content))
    "gemini" => Ok(ccs_load_gemini_messages(content))
    "opencode" | "openclaw" | "hermes" =>
      Ok(ccs_load_generic_json_messages(content))
    _ => Err("Unsupported provider: \{provider_id}")
  }
}

///|
async fn ccs_delete_session(
  provider_id : String,
  session_id : String,
  source_path : String,
) -> Result[Bool, String] {
  let provider = ccs_normalize_app_type(provider_id)
  if source_path.has_prefix("sqlite:") {
    return match provider {
      "opencode" => ccs_delete_opencode_sqlite_session(session_id, source_path)
      "hermes" => ccs_delete_hermes_sqlite_session(session_id, source_path)
      _ => Err("Unsupported SQLite session provider: \{provider_id}")
    }
  }
  guard @fsx.exists_as_file(source_path) else {
    return Err("session source not found: \{source_path}")
  }
  let ok_root = ccs_source_path_under_provider_roots(provider, source_path)
  guard ok_root else {
    return Err("Session source path is outside provider roots: \{source_path}")
  }
  let meta = match provider {
    "codex" => ccs_parse_codex_session(source_path)
    "claude" => ccs_parse_claude_session(source_path)
    "gemini" => ccs_parse_gemini_session(source_path)
    "opencode" | "openclaw" | "hermes" =>
      ccs_parse_generic_json_session(source_path, provider)
    _ => return Err("Unsupported provider: \{provider_id}")
  }
  match meta {
    Some(meta) if meta.session_id == session_id => ()
    Some(meta) =>
      return Err(
        "\{ccs_session_provider_label(provider)} session ID mismatch: expected \{session_id}, found \{meta.session_id}",
      )
    None =>
      return Err(
        "Failed to parse \{ccs_session_provider_label(provider)} session metadata: \{source_path}",
      )
  }
  @fsx.remove(source_path) catch {
    error =>
      return Err("Failed to delete session file \{source_path}: \{error}")
  }
  if provider == "claude" {
    let sibling = @pathx.join(
      @pathx.dirname(source_path),
      @pathx.stem(source_path),
    )
    if @fsx.exists(sibling) {
      @fsx.remove(sibling) catch {
        _ => ()
      }
    }
  }
  Ok(true)
}

///|
fn ccs_session_provider_label(provider : String) -> String {
  match provider {
    "codex" => "Codex"
    "claude" => "Claude"
    "gemini" => "Gemini"
    "opencode" => "OpenCode"
    "openclaw" => "OpenClaw"
    "hermes" => "Hermes"
    _ => provider
  }
}

///|
async fn ccs_source_path_under_provider_roots(
  provider : String,
  source_path : String,
) -> Bool {
  let source_resolved = @fsx.resolve(source_path) catch { _ => return false }
  for root in ccs_session_provider_roots(provider) {
    if !@fsx.exists(root) {
      continue
    }
    let root_resolved = @fsx.resolve(root) catch { _ => continue }
    if ccs_path_has_root(source_resolved, root_resolved) {
      return true
    }
  }
  false
}

///|
fn ccs_path_has_root(path : String, root : String) -> Bool {
  let clean_root = ccs_trim_trailing_slash(root)
  path == clean_root || path.has_prefix(clean_root + "/")
}

///|
fn ccs_trim_trailing_slash(path : String) -> String {
  let mut value = path
  while value.length() > 1 && value.has_suffix("/") {
    value = value[:value.length() - 1].to_owned()
  }
  value
}

///|
async fn ccs_collect_provider_session_files(provider : String) -> Array[String] {
  let files = []
  for root in ccs_session_provider_roots(provider) {
    match provider {
      "gemini" => ccs_collect_gemini_chat_files(root, files)
      "hermes" => ccs_collect_session_files(root, files, max_depth=1)
      _ => ccs_collect_session_files(root, files, max_depth=8)
    }
  }
  files
}

///|
fn ccs_session_provider_roots(provider : String) -> Array[String] {
  match ccs_normalize_app_type(provider) {
    "codex" =>
      [
        @pathx.join(ccs_config_dir("codex"), "sessions"),
        @pathx.join(ccs_config_dir("codex"), "archived_sessions"),
      ]
    "claude" => [@pathx.join(ccs_config_dir("claude"), "projects")]
    "gemini" => [@pathx.join(ccs_config_dir("gemini"), "tmp")]
    "opencode" => [ccs_opencode_data_dir()]
    "openclaw" => [@pathx.join(ccs_config_dir("openclaw"), "agents")]
    "hermes" => [@pathx.join(ccs_config_dir("hermes"), "sessions")]
    _ => []
  }
}

///|
fn ccs_opencode_data_dir() -> String {
  let xdg = @os.getenv("XDG_DATA_HOME") catch { _ => None }
  match xdg {
    Some(base) if !base.trim().is_empty() =>
      @pathx.join(base.trim(), "opencode")
    _ => @pathx.join(@pathx.join(ccs_home_dir(), ".local/share"), "opencode")
  }
}

///|
fn ccs_opencode_db_path() -> String {
  @pathx.join(ccs_opencode_data_dir(), "opencode.db")
}

///|
fn ccs_hermes_db_path() -> String {
  @pathx.join(ccs_config_dir("hermes"), "state.db")
}

///|
async fn ccs_scan_opencode_sessions() -> Array[CcsSessionMeta] {
  let sqlite_sessions = ccs_scan_opencode_sqlite_sessions()
  let result = sqlite_sessions.copy()
  for path in ccs_collect_provider_session_files("opencode") {
    match ccs_parse_generic_json_session(path, "opencode") {
      Some(meta) if !ccs_session_has_id(sqlite_sessions, meta.session_id) =>
        result.push(meta)
      _ => ()
    }
  }
  result
}

///|
async fn ccs_scan_hermes_sessions() -> Array[CcsSessionMeta] {
  let sqlite_sessions = ccs_scan_hermes_sqlite_sessions()
  let result = sqlite_sessions.copy()
  for path in ccs_collect_provider_session_files("hermes") {
    match ccs_parse_generic_json_session(path, "hermes") {
      Some(meta) if !ccs_session_has_id(sqlite_sessions, meta.session_id) =>
        result.push(meta)
      _ => ()
    }
  }
  result
}

///|
fn ccs_session_has_id(
  sessions : Array[CcsSessionMeta],
  session_id : String,
) -> Bool {
  sessions.any(fn(session) { session.session_id == session_id })
}

///|
async fn ccs_scan_opencode_sqlite_sessions() -> Array[CcsSessionMeta] {
  let db_path = ccs_opencode_db_path()
  if !@fsx.exists_as_file(db_path) {
    return []
  }
  let rows = match
    ccs_sqlite_json_rows(
      db_path,
      "SELECT id, title, directory, time_created, time_updated FROM session ORDER BY time_updated DESC",
      read_only=true,
    ) {
    Ok(rows) => rows
    Err(_) => return []
  }
  ccs_opencode_sqlite_rows_to_sessions(db_path, rows)
}

///|
fn ccs_opencode_sqlite_rows_to_sessions(
  db_path : String,
  rows : Array[Json],
) -> Array[CcsSessionMeta] {
  let sessions = []
  for row in rows {
    guard row is Object(obj) else { continue }
    guard ccs_json_string(obj.get("id")) is Some(session_id) else { continue }
    let directory = ccs_json_string(obj.get("directory")).unwrap_or("")
    let raw_title = ccs_json_string(obj.get("title")).unwrap_or("")
    let display_title = if raw_title.is_empty() {
      ccs_path_basename(directory)
    } else {
      Some(raw_title)
    }
    sessions.push(CcsSessionMeta::{
      provider_id: "opencode",
      session_id,
      title: display_title,
      summary: display_title,
      project_dir: if directory.is_empty() {
        None
      } else {
        Some(directory)
      },
      created_at: ccs_json_int64(obj.get("time_created")),
      last_active_at: ccs_json_int64(obj.get("time_updated")),
      source_path: Some("sqlite:\{db_path}:\{session_id}"),
      resume_command: Some("opencode session resume \{session_id}"),
    })
  }
  sessions
}

///|
async fn ccs_scan_hermes_sqlite_sessions() -> Array[CcsSessionMeta] {
  let db_path = ccs_hermes_db_path()
  if !@fsx.exists_as_file(db_path) {
    return []
  }
  let rows = match
    ccs_sqlite_json_rows(
      db_path,
      "SELECT * FROM sessions ORDER BY rowid DESC LIMIT 500",
      read_only=true,
    ) {
    Ok(rows) => rows
    Err(_) => return []
  }
  ccs_hermes_sqlite_rows_to_sessions(db_path, rows)
}

///|
fn ccs_hermes_sqlite_rows_to_sessions(
  db_path : String,
  rows : Array[Json],
) -> Array[CcsSessionMeta] {
  let sessions = []
  for row in rows {
    guard row is Object(obj) else { continue }
    guard ccs_json_string(obj.get("id")) is Some(session_id) else { continue }
    let title = match ccs_json_string(obj.get("title")) {
      Some(value) if !value.is_empty() =>
        Some(ccs_truncate_summary(value, ccs_session_title_max_chars))
      _ => None
    }
    let cwd = match
      ccs_first_string(
        ccs_json_string(obj.get("cwd")),
        ccs_json_string(obj.get("directory")),
      ) {
      Some(value) if !value.is_empty() => Some(value)
      _ => None
    }
    let started_at = ccs_first_timestamp(
      ccs_json_timestamp_ms(obj.get("started_at")),
      ccs_json_timestamp_ms(obj.get("created_at")),
    )
    let ended_at = ccs_first_timestamp(
      ccs_json_timestamp_ms(obj.get("ended_at")),
      ccs_json_timestamp_ms(obj.get("updated_at")),
    )
    sessions.push(CcsSessionMeta::{
      provider_id: "hermes",
      session_id,
      title,
      summary: None,
      project_dir: cwd,
      created_at: started_at,
      last_active_at: ccs_first_timestamp(ended_at, started_at),
      source_path: Some("sqlite:\{db_path}#\{session_id}"),
      resume_command: None,
    })
  }
  sessions
}

///|
async fn ccs_collect_session_files(
  root : String,
  files : Array[String],
  max_depth~ : Int,
) -> Unit {
  ccs_collect_session_files_at(root, files, depth=0, max_depth~)
}

///|
async fn ccs_collect_session_files_at(
  dir : String,
  files : Array[String],
  depth~ : Int,
  max_depth~ : Int,
) -> Unit {
  if depth > max_depth || !@fsx.exists(dir) {
    return
  }
  let entries = @fsx.list_directory(dir) catch { _ => return }
  for entry in entries {
    if entry.kind is @fsx.FileKind::Directory {
      ccs_collect_session_files_at(
        entry.path,
        files,
        depth=depth + 1,
        max_depth~,
      )
    } else if entry.kind is @fsx.FileKind::Regular &&
      ccs_session_file_name(entry.name) {
      files.push(entry.path)
    }
  }
}

///|
fn ccs_session_file_name(name : String) -> Bool {
  name.has_suffix(".jsonl") || name.has_suffix(".json")
}

///|
async fn ccs_collect_gemini_chat_files(
  tmp_dir : String,
  files : Array[String],
) -> Unit {
  if !@fsx.exists(tmp_dir) {
    return
  }
  let projects = @fsx.list_directory(tmp_dir) catch { _ => return }
  for project in projects {
    if !(project.kind is @fsx.FileKind::Directory) {
      continue
    }
    let chats_dir = @pathx.join(project.path, "chats")
    let chats = @fsx.list_directory(chats_dir) catch { _ => continue }
    for chat in chats {
      if chat.kind is @fsx.FileKind::Regular && ccs_session_file_name(chat.name) {
        files.push(chat.path)
      }
    }
  }
}

///|
async fn ccs_parse_codex_session(path : String) -> CcsSessionMeta? {
  let lines = ccs_read_nonempty_lines(path)
  if lines.is_empty() {
    return None
  }
  ccs_parse_codex_session_lines(lines, path)
}

///|
fn ccs_parse_codex_session_lines(
  lines : Array[String],
  path : String,
) -> CcsSessionMeta? {
  let head = ccs_head_lines(lines, 10)
  let tail = ccs_tail_lines(lines, 30)
  let mut session_id : String? = None
  let mut project_dir : String? = None
  let mut created_at : Int64? = None
  let mut first_user_message : String? = None
  for line in head {
    guard ccs_parse_json_line(line) is Some(value) else { continue }
    if created_at is None {
      created_at = ccs_json_timestamp_ms(ccs_json_get(value, "timestamp"))
    }
    if json_string_from_json(ccs_json_get(value, "type")) ==
      Some("session_meta") {
      if ccs_json_get(value, "payload") is Some(Object(payload)) {
        if ccs_is_subagent_source(payload.get("source")) {
          return None
        }
        if session_id is None {
          session_id = json_string_from_map_any(payload, ["id"])
        }
        if project_dir is None {
          project_dir = json_string_from_map_any(payload, ["cwd"])
        }
        match ccs_json_timestamp_ms(payload.get("timestamp")) {
          Some(ts) if created_at is None => created_at = Some(ts)
          _ => ()
        }
      }
    }
    if first_user_message is None &&
      json_string_from_json(ccs_json_get(value, "type")) ==
      Some("response_item") &&
      ccs_json_get(value, "payload") is Some(Object(payload)) &&
      json_string_from_map_any(payload, ["type"]) == Some("message") &&
      json_string_from_map_any(payload, ["role"]) == Some("user") {
      let text = ccs_extract_json_text(payload.get("content"))
      match ccs_codex_title_candidate(text) {
        Some(title) => first_user_message = Some(title)
        None => ()
      }
    }
  }
  let mut last_active_at : Int64? = None
  let mut summary : String? = None
  for line in ccs_reversed_lines(tail) {
    guard ccs_parse_json_line(line) is Some(value) else { continue }
    if last_active_at is None {
      last_active_at = ccs_json_timestamp_ms(ccs_json_get(value, "timestamp"))
    }
    if summary is None &&
      json_string_from_json(ccs_json_get(value, "type")) ==
      Some("response_item") &&
      ccs_json_get(value, "payload") is Some(Object(payload)) &&
      json_string_from_map_any(payload, ["type"]) == Some("message") {
      let text = ccs_extract_json_text(payload.get("content"))
      if !text.trim().is_empty() {
        summary = Some(ccs_truncate_summary(text, 160))
      }
    }
  }
  let id = match session_id {
    Some(value) => value
    None => ccs_infer_session_id_from_filename(path).unwrap_or("")
  }
  if id.is_empty() {
    return None
  }
  let title = match first_user_message {
    Some(value) =>
      Some(ccs_truncate_summary(value, ccs_session_title_max_chars))
    None =>
      match project_dir {
        Some(dir) => ccs_path_basename(dir)
        None => None
      }
  }
  Some(CcsSessionMeta::{
    provider_id: "codex",
    session_id: id,
    title,
    summary,
    project_dir,
    created_at,
    last_active_at,
    source_path: Some(path),
    resume_command: Some("codex resume \{id}"),
  })
}

///|
async fn ccs_parse_claude_session(path : String) -> CcsSessionMeta? {
  if @pathx.basename(path).has_prefix("agent-") {
    return None
  }
  let lines = ccs_read_nonempty_lines(path)
  if lines.is_empty() {
    return None
  }
  ccs_parse_claude_session_lines(lines, path)
}

///|
fn ccs_parse_claude_session_lines(
  lines : Array[String],
  path : String,
) -> CcsSessionMeta? {
  let head = ccs_head_lines(lines, 10)
  let tail = ccs_tail_lines(lines, 30)
  let mut session_id : String? = None
  let mut project_dir : String? = None
  let mut created_at : Int64? = None
  let mut first_user_message : String? = None
  for line in head {
    guard ccs_parse_json_line(line) is Some(value) else { continue }
    if session_id is None {
      session_id = json_string_from_json(ccs_json_get(value, "sessionId"))
    }
    if project_dir is None {
      project_dir = json_string_from_json(ccs_json_get(value, "cwd"))
    }
    if created_at is None {
      created_at = ccs_json_timestamp_ms(ccs_json_get(value, "timestamp"))
    }
    if first_user_message is None {
      let is_user = json_string_from_json(ccs_json_get(value, "type")) ==
        Some("user") ||
        (
          ccs_json_get(value, "message") is Some(Object(message)) &&
          json_string_from_map_any(message, ["role"]) == Some("user")
        )
      if is_user && ccs_json_get(value, "message") is Some(Object(message)) {
        let text = ccs_extract_json_text(message.get("content"))
        let trimmed = text.trim()
        if !trimmed.is_empty() &&
          !trimmed.contains("<local-command-caveat>") &&
          !trimmed.has_prefix("<command-name>") {
          first_user_message = Some(trimmed.to_owned())
        }
      }
    }
  }
  let mut last_active_at : Int64? = None
  let mut summary : String? = None
  let mut custom_title : String? = None
  for line in ccs_reversed_lines(tail) {
    guard ccs_parse_json_line(line) is Some(value) else { continue }
    if last_active_at is None {
      last_active_at = ccs_json_timestamp_ms(ccs_json_get(value, "timestamp"))
    }
    if custom_title is None &&
      json_string_from_json(ccs_json_get(value, "type")) == Some("custom-title") {
      match json_string_from_json(ccs_json_get(value, "customTitle")) {
        Some(value) if !value.trim().is_empty() =>
          custom_title = Some(value.trim().to_owned())
        _ => ()
      }
    }
    if summary is None &&
      ccs_json_get(value, "isMeta") != Some(Json::boolean(true)) &&
      ccs_json_get(value, "message") is Some(Object(message)) {
      let text = ccs_extract_json_text(message.get("content"))
      if !text.trim().is_empty() {
        summary = Some(ccs_truncate_summary(text, 160))
      }
    }
  }
  let id = match session_id {
    Some(value) => value
    None => ccs_infer_session_id_from_filename(path).unwrap_or("")
  }
  if id.is_empty() {
    return None
  }
  let title = match custom_title {
    Some(value) =>
      Some(ccs_truncate_summary(value, ccs_session_title_max_chars))
    None =>
      match first_user_message {
        Some(value) =>
          Some(ccs_truncate_summary(value, ccs_session_title_max_chars))
        None =>
          match project_dir {
            Some(dir) => ccs_path_basename(dir)
            None => None
          }
      }
  }
  Some(CcsSessionMeta::{
    provider_id: "claude",
    session_id: id,
    title,
    summary,
    project_dir,
    created_at,
    last_active_at,
    source_path: Some(path),
    resume_command: Some("claude --resume \{id}"),
  })
}

///|
async fn ccs_parse_gemini_session(path : String) -> CcsSessionMeta? {
  let lines = ccs_read_nonempty_lines(path)
  if lines.is_empty() {
    return None
  }
  ccs_parse_gemini_session_lines(lines, path)
}

///|
fn ccs_parse_gemini_session_lines(
  lines : Array[String],
  path : String,
) -> CcsSessionMeta? {
  let mut session_id = ccs_infer_session_id_from_filename(path).unwrap_or("")
  let mut project_dir : String? = None
  let mut created_at : Int64? = None
  let mut last_active_at : Int64? = None
  let mut first_user_message : String? = None
  let mut summary : String? = None
  for line in lines {
    guard ccs_parse_json_line(line) is Some(value) else { continue }
    if value is Object(obj) {
      match json_string_from_map_any(obj, ["sessionId", "id"]) {
        Some(value) if !value.is_empty() => session_id = value
        _ => ()
      }
      if project_dir is None {
        project_dir = json_string_from_map_any(obj, [
          "cwd", "projectDir", "project_dir",
        ])
      }
    }
    match
      ccs_first_timestamp(
        ccs_json_timestamp_ms(ccs_json_get(value, "timestamp")),
        ccs_json_timestamp_ms(ccs_json_get(value, "ts")),
      ) {
      Some(ts) => {
        if created_at is None {
          created_at = Some(ts)
        }
        last_active_at = Some(ts)
      }
      None => ()
    }
    let role = ccs_first_string(
      json_string_from_json(ccs_json_get(value, "role")),
      match ccs_json_get(value, "message") {
        Some(Object(message)) => json_string_from_map_any(message, ["role"])
        _ => None
      },
    )
    let content = ccs_extract_json_text(
      match ccs_json_get(value, "content") {
        Some(Null) | None =>
          match ccs_json_get(value, "message") {
            Some(Object(message)) => message.get("content")
            _ => None
          }
        other => other
      },
    )
    if !content.trim().is_empty() {
      if role == Some("user") && first_user_message is None {
        first_user_message = Some(content.trim().to_owned())
      }
      summary = Some(ccs_truncate_summary(content, 160))
    }
  }
  if session_id.is_empty() {
    return None
  }
  Some(CcsSessionMeta::{
    provider_id: "gemini",
    session_id,
    title: first_user_message.map(fn(value) {
      ccs_truncate_summary(value, ccs_session_title_max_chars)
    }),
    summary,
    project_dir,
    created_at,
    last_active_at,
    source_path: Some(path),
    resume_command: None,
  })
}

///|
async fn ccs_parse_generic_json_session(
  path : String,
  provider : String,
) -> CcsSessionMeta? {
  let lines = ccs_read_nonempty_lines(path)
  if lines.is_empty() {
    return None
  }
  ccs_parse_generic_json_session_lines(
    lines,
    path,
    ccs_normalize_app_type(provider),
  )
}

///|
fn ccs_parse_generic_json_session_lines(
  lines : Array[String],
  path : String,
  provider : String,
) -> CcsSessionMeta? {
  let mut session_id : String? = None
  let mut title : String? = None
  let mut project_dir : String? = None
  let mut first_user_message : String? = None
  let mut created_at : Int64? = None
  let mut last_active_at : Int64? = None
  for line in lines {
    guard ccs_parse_json_line(line) is Some(value) else { continue }
    if value is Object(obj) {
      if session_id is None {
        session_id = json_string_from_map_any(obj, [
          "id", "sessionId", "session_id",
        ])
      }
      if title is None {
        title = json_string_from_map_any(obj, ["title"])
      }
      if project_dir is None {
        project_dir = json_string_from_map_any(obj, [
          "cwd", "directory", "projectDir", "project_dir",
        ])
      }
      let value_type = json_string_from_map_any(obj, ["type"])
      let message = match obj.get("message") {
        Some(Object(message)) => Some(message)
        _ => None
      }
      let role = ccs_first_string(
        json_string_from_map_any(obj, ["role"]),
        match message {
          Some(message) => json_string_from_map_any(message, ["role"])
          None => None
        },
      )
      let content = ccs_extract_json_text(
        match obj.get("content") {
          Some(value) => Some(value)
          None =>
            match message {
              Some(message) => message.get("content")
              None => None
            }
        },
      )
      if role == Some("user") &&
        first_user_message is None &&
        !content.trim().is_empty() {
        first_user_message = Some(content.trim().to_owned())
      }
      let ts = ccs_first_timestamp(
        ccs_json_timestamp_ms(obj.get("timestamp")),
        ccs_json_timestamp_ms(obj.get("ts")),
      )
      match ts {
        Some(ts) => {
          if created_at is None {
            created_at = Some(ts)
          }
          last_active_at = Some(ts)
        }
        None => ()
      }
      if value_type == Some("session") || value_type == Some("init") {
        continue
      }
    }
  }
  let id = match session_id {
    Some(value) if !value.is_empty() => value
    _ => ccs_infer_session_id_from_filename(path).unwrap_or("")
  }
  if id.is_empty() {
    return None
  }
  Some(CcsSessionMeta::{
    provider_id: provider,
    session_id: id,
    title: ccs_first_string(
      title,
      first_user_message.map(fn(value) {
        ccs_truncate_summary(value, ccs_session_title_max_chars)
      }),
    ),
    summary: first_user_message.map(fn(value) {
      ccs_truncate_summary(value, 160)
    }),
    project_dir,
    created_at,
    last_active_at,
    source_path: Some(path),
    resume_command: None,
  })
}

///|
priv struct CcsSqliteSessionSource {
  db_path : String
  session_id : String
}

///|
async fn ccs_load_opencode_sqlite_messages(
  source_path : String,
) -> Result[Array[CcsSessionMessage], String] {
  guard ccs_parse_opencode_sqlite_source(source_path) is Some(source) else {
    return Err("Invalid SQLite source reference: \{source_path}")
  }
  let query = (
    #|SELECT
    #|  m.id AS message_id,
    #|  m.time_created AS ts,
    #|  m.data AS message_data,
    #|  json_group_array(p.data) AS parts
    #|FROM message m
    #|LEFT JOIN part p ON p.session_id = m.session_id AND p.message_id = m.id
    #|WHERE m.session_id = $SESSION
    #|GROUP BY m.id, m.time_created, m.data
    #|ORDER BY m.time_created ASC;
  ).replace_all(old="$SESSION", new=ccs_sqlite_quote(source.session_id))
  let rows = match ccs_sqlite_json_rows(source.db_path, query, read_only=true) {
    Ok(rows) => rows
    Err(error) => return Err(error)
  }
  Ok(ccs_opencode_sqlite_rows_to_messages(rows))
}

///|
fn ccs_opencode_sqlite_rows_to_messages(
  rows : Array[Json],
) -> Array[CcsSessionMessage] {
  let messages = []
  for row in rows {
    guard row is Object(obj) else { continue }
    guard ccs_json_string(obj.get("message_data")) is Some(message_data) else {
      continue
    }
    let message_value = @json.parse(message_data) catch { _ => Json::null() }
    let role = (match message_value {
      Object(message) => json_string_from_map_any(message, ["role"])
      _ => None
    }).unwrap_or("unknown")
    let parts = match ccs_json_string(obj.get("parts")) {
      Some(parts_json) => ccs_opencode_parts_text(parts_json)
      None => ""
    }
    if parts.trim().is_empty() {
      continue
    }
    messages.push(CcsSessionMessage::{
      role,
      content: parts,
      ts: ccs_json_int64(obj.get("ts")),
    })
  }
  messages
}

///|
fn ccs_opencode_parts_text(parts_json : String) -> String {
  let parsed = @json.parse(parts_json) catch { _ => return "" }
  guard parsed is Array(parts) else { return "" }
  let texts = []
  for raw_part in parts {
    guard ccs_json_string(Some(raw_part)) is Some(part_text) else { continue }
    let part_json = @json.parse(part_text) catch { _ => continue }
    match ccs_opencode_part_text(part_json) {
      Some(text) if !text.trim().is_empty() => texts.push(text)
      _ => ()
    }
  }
  texts.join("\n")
}

///|
fn ccs_opencode_part_text(part : Json) -> String? {
  guard part is Object(obj) else { return None }
  match json_string_from_map_any(obj, ["type"]) {
    Some("text") =>
      match json_string_from_map_any(obj, ["text"]) {
        Some(text) if !text.trim().is_empty() => Some(text)
        _ => None
      }
    Some("tool") =>
      Some(
        "[Tool: \{json_string_from_map_any(obj, ["tool"]).unwrap_or("unknown")}]",
      )
    _ => None
  }
}

///|
async fn ccs_load_hermes_sqlite_messages(
  source_path : String,
) -> Result[Array[CcsSessionMessage], String] {
  guard ccs_parse_hermes_sqlite_source(source_path) is Some(source) else {
    return Err("Invalid SQLite source reference: \{source_path}")
  }
  let query = (
    #|SELECT role, content, created_at
    #|FROM messages
    #|WHERE session_id = $SESSION
    #|ORDER BY created_at ASC;
  ).replace_all(old="$SESSION", new=ccs_sqlite_quote(source.session_id))
  let rows = match ccs_sqlite_json_rows(source.db_path, query, read_only=true) {
    Ok(rows) => rows
    Err(error) => return Err(error)
  }
  let messages = []
  for row in rows {
    guard row is Object(obj) else { continue }
    guard ccs_json_string(obj.get("role")) is Some(role) else { continue }
    guard ccs_json_string(obj.get("content")) is Some(content) else { continue }
    if content.trim().is_empty() {
      continue
    }
    messages.push(CcsSessionMessage::{
      role,
      content,
      ts: ccs_json_timestamp_ms(obj.get("created_at")),
    })
  }
  Ok(messages)
}

///|
async fn ccs_delete_opencode_sqlite_session(
  session_id : String,
  source_path : String,
) -> Result[Bool, String] {
  ccs_delete_opencode_sqlite_session_with_expected(
    session_id,
    source_path,
    ccs_opencode_db_path(),
  )
}

///|
async fn ccs_delete_opencode_sqlite_session_with_expected(
  session_id : String,
  source_path : String,
  expected_db_path : String,
) -> Result[Bool, String] {
  guard ccs_parse_opencode_sqlite_source(source_path) is Some(source) else {
    return Err("Invalid SQLite source reference: \{source_path}")
  }
  if source.session_id != session_id {
    return Err(
      "OpenCode SQLite session ID mismatch: expected \{session_id}, found \{source.session_id}",
    )
  }
  match
    ccs_validate_sqlite_db_path(source.db_path, expected_db_path, "OpenCode") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let deleted = match
    ccs_sqlite_count_session(source.db_path, "session", "id", session_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let quoted = ccs_sqlite_quote(session_id)
  let query = (
    #|BEGIN;
    #|DELETE FROM part WHERE session_id = $SESSION;
    #|DELETE FROM message WHERE session_id = $SESSION;
    #|DELETE FROM session WHERE id = $SESSION;
    #|COMMIT;
  ).replace_all(old="$SESSION", new=quoted)
  match ccs_sqlite_exec(source.db_path, query) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok(deleted > 0)
}

///|
async fn ccs_delete_hermes_sqlite_session(
  session_id : String,
  source_path : String,
) -> Result[Bool, String] {
  ccs_delete_hermes_sqlite_session_with_expected(
    session_id,
    source_path,
    ccs_hermes_db_path(),
  )
}

///|
async fn ccs_delete_hermes_sqlite_session_with_expected(
  session_id : String,
  source_path : String,
  expected_db_path : String,
) -> Result[Bool, String] {
  guard ccs_parse_hermes_sqlite_source(source_path) is Some(source) else {
    return Err("Invalid SQLite source reference: \{source_path}")
  }
  if source.session_id != session_id {
    return Err(
      "Hermes SQLite session ID mismatch: expected \{session_id}, found \{source.session_id}",
    )
  }
  match
    ccs_validate_sqlite_db_path(source.db_path, expected_db_path, "Hermes") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let deleted = match
    ccs_sqlite_count_session(source.db_path, "sessions", "id", session_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let quoted = ccs_sqlite_quote(session_id)
  ignore(
    ccs_sqlite_exec(
      source.db_path,
      "DELETE FROM messages WHERE session_id = \{quoted};",
    ),
  )
  match
    ccs_sqlite_exec(
      source.db_path,
      "DELETE FROM sessions WHERE id = \{quoted};",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok(deleted > 0)
}

///|
fn ccs_parse_opencode_sqlite_source(source : String) -> CcsSqliteSessionSource? {
  guard source.has_prefix("sqlite:") else { return None }
  let rest = source["sqlite:".length():].to_owned()
  let sep = ccs_last_index_of(rest, ":ses_")
  guard sep >= 0 else { return None }
  let db_path = rest[:sep].to_owned()
  let session_id = rest[sep + 1:].to_owned()
  if db_path.is_empty() || session_id.is_empty() {
    None
  } else {
    Some(CcsSqliteSessionSource::{ db_path, session_id })
  }
}

///|
fn ccs_parse_hermes_sqlite_source(source : String) -> CcsSqliteSessionSource? {
  guard source.has_prefix("sqlite:") else { return None }
  let rest = source["sqlite:".length():].to_owned()
  let sep = ccs_last_index_of(rest, "#")
  guard sep >= 0 else { return None }
  let db_path = rest[:sep].to_owned()
  let session_id = rest[sep + 1:].to_owned()
  if db_path.is_empty() || session_id.is_empty() {
    None
  } else {
    Some(CcsSqliteSessionSource::{ db_path, session_id })
  }
}

///|
fn ccs_last_index_of(value : String, needle : String) -> Int {
  let mut offset = 0
  let mut last = -1
  while offset < value.length() {
    match value[offset:].find(needle) {
      Some(index) => {
        last = offset + index
        offset = last + 1
      }
      None => return last
    }
  }
  last
}

///|
async fn ccs_validate_sqlite_db_path(
  db_path : String,
  expected_path : String,
  provider_label : String,
) -> Result[Unit, String] {
  let db_resolved = @fsx.resolve(db_path) catch {
    error => return Err("Failed to canonicalize SQLite database path: \{error}")
  }
  let expected_resolved = @fsx.resolve(expected_path) catch {
    error =>
      return Err(
        "Failed to canonicalize expected \{provider_label} database path: \{error}",
      )
  }
  if db_resolved != expected_resolved {
    return Err("SQLite path does not match expected \{provider_label} database")
  }
  Ok(())
}

///|
async fn ccs_sqlite_count_session(
  db_path : String,
  table : String,
  id_column : String,
  session_id : String,
) -> Result[Int, String] {
  let rows = match
    ccs_sqlite_json_rows(
      db_path,
      "SELECT COUNT(*) AS deleted FROM \{table} WHERE \{id_column} = \{ccs_sqlite_quote(session_id)};",
      read_only=true,
    ) {
    Ok(rows) => rows
    Err(error) => return Err(error)
  }
  guard rows.length() > 0 && rows[0] is Object(obj) else { return Ok(0) }
  Ok(ccs_json_int64(obj.get("deleted")).unwrap_or(0L).to_int())
}

///|
async fn ccs_sqlite_json_rows(
  db_path : String,
  query : String,
  read_only~ : Bool,
) -> Result[Array[Json], String] {
  let process = try {
    if read_only {
      @spawn.spawn(
        "sqlite3",
        ["-readonly", "-json", db_path, query],
        timeout=10000,
      )
    } else {
      @spawn.spawn("sqlite3", ["-json", db_path, query], timeout=10000)
    }
  } catch {
    error => return Err("SQLite query failed \{db_path}: \{error}")
  }
  if process.status != 0 {
    return Err("SQLite query failed \{db_path}: \{process.stderr.trim()}")
  }
  if process.stdout.trim().is_empty() {
    return Ok([])
  }
  let parsed = @json.parse(process.stdout) catch {
    error => return Err("SQLite JSON parse failed: \{error}")
  }
  guard parsed is Array(rows) else {
    return Err("SQLite JSON output was not an array")
  }
  Ok(rows)
}

///|
async fn ccs_sqlite_exec(
  db_path : String,
  query : String,
) -> Result[Unit, String] {
  let process = @spawn.spawn("sqlite3", [db_path, query], timeout=10000) catch {
    error => return Err("SQLite query failed \{db_path}: \{error}")
  }
  if process.status != 0 {
    return Err("SQLite query failed \{db_path}: \{process.stderr.trim()}")
  }
  Ok(())
}

///|
fn ccs_sqlite_quote(value : String) -> String {
  "'\{value.replace_all(old="'", new="''")}'"
}

///|
fn ccs_json_string(value : Json?) -> String? {
  match value {
    Some(String(value)) => Some(value)
    Some(Number(n, ..)) => Some(n.to_string())
    _ => None
  }
}

///|
fn ccs_json_int64(value : Json?) -> Int64? {
  match value {
    Some(Number(n, ..)) => Some(n.to_int64())
    Some(String(raw)) =>
      Some(@string.parse_int64(raw.trim().to_owned(), base=10)) catch {
        _ => None
      }
    _ => None
  }
}

///|
fn ccs_load_codex_messages(content : String) -> Array[CcsSessionMessage] {
  let messages = []
  for line in ccs_nonempty_lines_from_content(content) {
    guard ccs_parse_json_line(line) is Some(value) else { continue }
    guard json_string_from_json(ccs_json_get(value, "type")) ==
      Some("response_item") else {
      continue
    }
    guard ccs_json_get(value, "payload") is Some(Object(payload)) else {
      continue
    }
    let payload_type = json_string_from_map_any(payload, ["type"]).unwrap_or("")
    let (role, message) = match payload_type {
      "message" =>
        (
          json_string_from_map_any(payload, ["role"]).unwrap_or("unknown"),
          ccs_extract_json_text(payload.get("content")),
        )
      "function_call" =>
        (
          "assistant",
          "[Tool: \{json_string_from_map_any(payload, ["name"]).unwrap_or("unknown")}]",
        )
      "function_call_output" =>
        ("tool", json_string_from_map_any(payload, ["output"]).unwrap_or(""))
      _ => continue
    }
    if message.trim().is_empty() {
      continue
    }
    messages.push(CcsSessionMessage::{
      role,
      content: message,
      ts: ccs_json_timestamp_ms(ccs_json_get(value, "timestamp")),
    })
  }
  messages
}

///|
fn ccs_load_claude_messages(content : String) -> Array[CcsSessionMessage] {
  let messages = []
  for line in ccs_nonempty_lines_from_content(content) {
    guard ccs_parse_json_line(line) is Some(value) else { continue }
    if ccs_json_get(value, "isMeta") == Some(Json::boolean(true)) {
      continue
    }
    guard ccs_json_get(value, "message") is Some(Object(message)) else {
      continue
    }
    let mut role = json_string_from_map_any(message, ["role"]).unwrap_or(
      "unknown",
    )
    match message.get("content") {
      Some(Array(items)) if role == "user" &&
        !items.is_empty() &&
        items.all(fn(item) {
          item is Object(obj) &&
          json_string_from_map_any(obj, ["type"]) == Some("tool_result")
        }) => role = "tool"
      _ => ()
    }
    let text = ccs_extract_json_text(message.get("content"))
    if text.trim().is_empty() {
      continue
    }
    messages.push(CcsSessionMessage::{
      role,
      content: text,
      ts: ccs_json_timestamp_ms(ccs_json_get(value, "timestamp")),
    })
  }
  messages
}

///|
fn ccs_load_gemini_messages(content : String) -> Array[CcsSessionMessage] {
  ccs_load_generic_json_messages(content)
}

///|
fn ccs_load_generic_json_messages(content : String) -> Array[CcsSessionMessage] {
  let messages = []
  for line in ccs_nonempty_lines_from_content(content) {
    guard ccs_parse_json_line(line) is Some(value) else { continue }
    let (role, content_value, ts_value) = match value {
      Object(obj) =>
        if json_string_from_map_any(obj, ["type"]) == Some("message") &&
          obj.get("message") is Some(Object(message)) {
          (
            json_string_from_map_any(message, ["role"]),
            message.get("content"),
            ccs_first_json(obj.get("timestamp"), message.get("ts")),
          )
        } else {
          (
            json_string_from_map_any(obj, ["role"]),
            obj.get("content"),
            ccs_first_json(obj.get("timestamp"), obj.get("ts")),
          )
        }
      _ => (None, None, None)
    }
    guard role is Some(role) else { continue }
    let text = ccs_extract_json_text(content_value)
    if text.trim().is_empty() {
      continue
    }
    messages.push(CcsSessionMessage::{
      role,
      content: text,
      ts: ccs_json_timestamp_ms(ts_value),
    })
  }
  messages
}

///|
async fn ccs_read_nonempty_lines(path : String) -> Array[String] {
  let content = ccs_read_session_file_text(path) catch { _ => return [] }
  ccs_nonempty_lines_from_content(content)
}

///|
async fn ccs_read_session_file_text(path : String) -> String {
  let file = @fs.open(path, mode=@fs.Mode::ReadOnly)
  defer file.close()
  let size = file.size() catch { _ => ccs_session_read_cap.to_int64() }
  let limit = if size < ccs_session_read_cap.to_int64() {
    size.to_int()
  } else {
    ccs_session_read_cap
  }
  if limit <= 0 {
    return ""
  }
  let buf = FixedArray::make(limit, b'\x00')
  let n = file.read_at(buf, position=0L, len=limit) catch { _ => 0 }
  if n <= 0 {
    return ""
  }
  let bytes = buf.unsafe_reinterpret_as_bytes()
  @encoding/utf8.decode(bytes[:n])
}

///|
fn ccs_nonempty_lines_from_content(content : String) -> Array[String] {
  let lines = []
  for raw in content.split("\n") {
    let line = raw.trim()
    if !line.is_empty() {
      lines.push(line.to_owned())
    }
  }
  lines
}

///|
fn ccs_head_lines(lines : Array[String], count : Int) -> Array[String] {
  let result = []
  let limit = if lines.length() < count { lines.length() } else { count }
  for i in 0..<limit {
    result.push(lines[i])
  }
  result
}

///|
fn ccs_tail_lines(lines : Array[String], count : Int) -> Array[String] {
  let result = []
  let start = if lines.length() > count { lines.length() - count } else { 0 }
  for i in start..<lines.length() {
    result.push(lines[i])
  }
  result
}

///|
fn ccs_reversed_lines(lines : Array[String]) -> Array[String] {
  let result = []
  if lines.is_empty() {
    return result
  }
  for i = lines.length() - 1; i >= 0; i = i - 1 {
    result.push(lines[i])
  }
  result
}

///|
fn ccs_parse_json_line(line : String) -> Json? {
  let parsed = @json.parse(line) catch { _ => return None }
  Some(parsed)
}

///|
fn ccs_json_get(value : Json, key : String) -> Json? {
  match value {
    Object(obj) => obj.get(key)
    _ => None
  }
}

///|
fn ccs_first_string(first : String?, second : String?) -> String? {
  match first {
    Some(value) => Some(value)
    None => second
  }
}

///|
fn ccs_first_timestamp(first : Int64?, second : Int64?) -> Int64? {
  match first {
    Some(value) => Some(value)
    None => second
  }
}

///|
fn ccs_first_json(first : Json?, second : Json?) -> Json? {
  match first {
    Some(value) => Some(value)
    None => second
  }
}

///|
fn ccs_json_timestamp_ms(value : Json?) -> Int64? {
  match value {
    Some(Number(n, ..)) => {
      let raw = n.to_int64()
      if raw > 1_000_000_000_000L {
        Some(raw)
      } else {
        Some(raw * 1000L)
      }
    }
    Some(String(raw)) => {
      let trimmed = raw.trim()
      if trimmed.is_empty() {
        None
      } else {
        let parsed_int = try
          @string.parse_int64(trimmed.to_owned(), base=10)
        catch {
          _ => None
        } noraise {
          parsed => Some(parsed)
        }
        match parsed_int {
          Some(raw) =>
            if raw > 1_000_000_000_000L {
              Some(raw)
            } else {
              Some(raw * 1000L)
            }
          None =>
            match parse_session_timestamp_seconds(trimmed.to_owned()) {
              Some(seconds) => Some(seconds.to_int64() * 1000L)
              None => None
            }
        }
      }
    }
    _ => None
  }
}

///|
fn json_string_from_json(value : Json?) -> String? {
  match value {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn ccs_extract_json_text(content : Json?) -> String {
  match content {
    Some(String(text)) => text
    Some(Array(items)) => {
      let parts = []
      for item in items {
        match ccs_extract_json_text_item(item) {
          Some(text) if !text.trim().is_empty() => parts.push(text)
          _ => ()
        }
      }
      parts.join("\n")
    }
    Some(Object(obj)) => json_string_from_map_any(obj, ["text"]).unwrap_or("")
    _ => ""
  }
}

///|
fn ccs_extract_json_text_item(item : Json) -> String? {
  guard item is Object(obj) else { return None }
  let item_type = json_string_from_map_any(obj, ["type"]).unwrap_or("")
  if item_type == "tool_use" {
    return Some(
      "[Tool: \{json_string_from_map_any(obj, ["name"]).unwrap_or("unknown")}]",
    )
  }
  if item_type == "tool_result" {
    match obj.get("content") {
      Some(content) => {
        let text = ccs_extract_json_text(Some(content))
        if text.is_empty() {
          return None
        }
        return Some(text)
      }
      None => return None
    }
  }
  for key in ["text", "input_text", "output_text"] {
    match json_string_from_map_any(obj, [key]) {
      Some(text) => return Some(text)
      None => ()
    }
  }
  match obj.get("content") {
    Some(content) => {
      let text = ccs_extract_json_text(Some(content))
      if text.is_empty() {
        None
      } else {
        Some(text)
      }
    }
    None => None
  }
}

///|
fn ccs_truncate_summary(text : String, max_chars : Int) -> String {
  let trimmed = text.trim()
  if trimmed.length() <= max_chars {
    trimmed.to_owned()
  } else {
    trimmed[:max_chars].to_owned() + "..."
  }
}

///|
fn ccs_path_basename(value : String) -> String? {
  let trimmed = value.trim()
  if trimmed.is_empty() {
    None
  } else {
    let base = @pathx.basename(trimmed)
    if base.is_empty() {
      None
    } else {
      Some(base.to_owned())
    }
  }
}

///|
fn ccs_infer_session_id_from_filename(path : String) -> String? {
  let stem = @pathx.stem(path).to_owned()
  if stem.is_empty() {
    None
  } else {
    Some(stem)
  }
}

///|
fn ccs_is_subagent_source(source : Json?) -> Bool {
  match source {
    Some(String(value)) => value.to_lower().contains("subagent")
    Some(Object(obj)) =>
      json_string_from_map_any(obj, ["type", "kind"])
      .map(fn(value) { value.to_lower().contains("subagent") })
      .unwrap_or(false)
    _ => false
  }
}

///|
fn ccs_codex_title_candidate(text : String) -> String? {
  let trimmed = text.trim()
  if trimmed.is_empty() {
    return None
  }
  let vscode_prefix = "# Context from my IDE setup:"
  if trimmed.has_prefix(vscode_prefix) {
    match trimmed.find("my request for codex") {
      Some(index) => {
        let candidate = trimmed[index + "my request for codex".length():].trim()
        if candidate.is_empty() {
          None
        } else {
          Some(candidate.to_owned())
        }
      }
      None => None
    }
  } else {
    Some(trimmed.to_owned())
  }
}
