///|
const CLAUDE_SESSION_REQUEST_ID_PREFIX : String = "session:"

///|
const SESSION_PROXY_DEDUP_WINDOW_SECONDS : Int = 600

///|
pub struct SessionSyncResult {
  mut imported : Int
  mut skipped : Int
  mut files_scanned : Int
  errors : Array[String]
}

///|
pub struct SessionFileSyncState {
  last_modified : Int64
  last_line_offset : Int
}

///|
priv struct ParsedClaudeSessionUsage {
  message_id : String
  model : String
  usage : TokenUsage
  stop_reason : String?
  timestamp : String?
  session_id : String?
}

///|
priv struct CumulativeSessionTokens {
  input : Int
  cached_input : Int
  output : Int
}

///|
priv struct DeltaSessionTokens {
  input : Int
  cached_input : Int
  output : Int
}

///|
priv struct CodexFileParseState {
  mut session_id : String?
  mut current_model : String
  mut prev_total : CumulativeSessionTokens?
  mut event_index : Int
}

///|
priv struct GeminiSessionTokens {
  input : Int
  output : Int
  cached : Int
  thoughts : Int
}

///|
pub fn SessionSyncResult::new() -> SessionSyncResult {
  { imported: 0, skipped: 0, files_scanned: 0, errors: [] }
}

///|
pub fn SessionSyncResult::to_json(self : SessionSyncResult) -> Json {
  {
    "imported": Json::number(self.imported.to_double()),
    "skipped": Json::number(self.skipped.to_double()),
    "filesScanned": Json::number(self.files_scanned.to_double()),
    "errors": Json::array(self.errors.map(fn(error) { Json::string(error) })),
  }.to_json()
}

///|
pub fn SessionFileSyncState::new(
  last_modified~ : Int64,
  last_line_offset~ : Int,
) -> SessionFileSyncState {
  { last_modified, last_line_offset }
}

///|
pub fn default_claude_projects_dir() -> String {
  let home = @os.home() catch { _ => "" }
  if home.is_empty() {
    ".claude/projects"
  } else {
    @pathx.join(home, ".claude/projects")
  }
}

///|
pub fn default_codex_config_dir() -> String {
  let home = @os.home() catch { _ => "" }
  if home.is_empty() {
    ".codex"
  } else {
    @pathx.join(home, ".codex")
  }
}

///|
pub fn default_gemini_dir() -> String {
  let home = @os.home() catch { _ => "" }
  if home.is_empty() {
    ".gemini"
  } else {
    @pathx.join(home, ".gemini")
  }
}

///|
pub async fn TrafficStats::sync_session_logs(
  self : TrafficStats,
  claude_projects_dir? : String = default_claude_projects_dir(),
  codex_dir? : String = default_codex_config_dir(),
  gemini_dir? : String = default_gemini_dir(),
) -> SessionSyncResult {
  let result = self.sync_claude_session_logs(projects_dir=claude_projects_dir)
  let codex_result = self.sync_codex_session_logs(codex_dir~)
  result.imported += codex_result.imported
  result.skipped += codex_result.skipped
  result.files_scanned += codex_result.files_scanned
  result.errors.append(codex_result.errors)
  let gemini_result = self.sync_gemini_session_logs(gemini_dir~)
  result.imported += gemini_result.imported
  result.skipped += gemini_result.skipped
  result.files_scanned += gemini_result.files_scanned
  result.errors.append(gemini_result.errors)
  result
}

///|
pub async fn TrafficStats::sync_claude_session_logs(
  self : TrafficStats,
  projects_dir? : String = default_claude_projects_dir(),
) -> SessionSyncResult {
  let result = SessionSyncResult::new()
  if !@fsx.exists(projects_dir) {
    return result
  }
  let files = collect_claude_jsonl_files(projects_dir)
  for file_path in files {
    result.files_scanned += 1
    try {
      let stat = @fsx.stat(file_path)
      let content = @fsx.read_file(file_path)
      let file_result = self.ingest_claude_session_jsonl(
        file_path~,
        content~,
        last_modified=stat.mtime(),
      )
      result.imported += file_result.imported
      result.skipped += file_result.skipped
      result.errors.append(file_result.errors)
    } catch {
      error => result.errors.push("\{file_path}: \{error}")
    }
  }
  result
}

///|
pub fn TrafficStats::ingest_claude_session_jsonl(
  self : TrafficStats,
  file_path~ : String,
  content~ : String,
  last_modified~ : Int64,
) -> SessionSyncResult {
  let result = SessionSyncResult::new()
  result.files_scanned = 1
  let existing_state = self.session_sync_state.get(file_path)
  if existing_state is Some(state) && last_modified <= state.last_modified {
    return result
  }
  let last_offset = match existing_state {
    Some(state) => state.last_line_offset
    None => 0
  }
  let messages : Map[String, ParsedClaudeSessionUsage] = Map([], capacity=0)
  let mut line_offset = 0
  let mut current_session_id : String? = None
  for line_view in content.split("\n") {
    line_offset += 1
    if line_offset <= last_offset {
      continue
    }
    let line = line_view.to_owned().trim()
    if line.is_empty() {
      continue
    }
    let parsed = @json.parse(line) catch { _ => continue }
    if current_session_id is None {
      current_session_id = session_json_string(parsed, "sessionId")
    }
    guard parsed is Object(root) else { continue }
    guard root.get("type") is Some(String("assistant")) else { continue }
    guard root.get("message") is Some(Object(message)) else { continue }
    guard message.get("id") is Some(String(message_id)) else { continue }
    guard message.get("usage") is Some(Object(usage_json)) else { continue }
    let usage = TokenUsage::new(
      input_tokens=json_int_or_zero(usage_json, "input_tokens"),
      output_tokens=json_int_or_zero(usage_json, "output_tokens"),
      cache_read_tokens=json_int_or_zero(usage_json, "cache_read_input_tokens"),
      cache_creation_tokens=json_int_or_zero(
        usage_json, "cache_creation_input_tokens",
      ),
      model=session_map_string(message, "model"),
      message_id=Some(message_id),
    )
    let parsed_usage : ParsedClaudeSessionUsage = {
      message_id,
      model: usage.model.unwrap_or("unknown"),
      usage,
      stop_reason: session_map_string(message, "stop_reason"),
      timestamp: session_map_string(root, "timestamp"),
      session_id: current_session_id,
    }
    if should_replace_claude_session_usage(
        messages.get(message_id),
        parsed_usage,
      ) {
      messages.set(message_id, parsed_usage)
    }
  }
  for message_id in messages.keys() {
    guard messages.get(message_id) is Some(message) else { continue }
    if !message.usage.has_billable_tokens() {
      continue
    }
    let request_id = "\{CLAUDE_SESSION_REQUEST_ID_PREFIX}\{message.message_id}"
    if self.should_skip_session_insert(
        request_id,
        app_type="claude",
        model=message.model,
        usage=message.usage,
        created_at=session_timestamp_seconds(message.timestamp),
      ) {
      result.skipped += 1
      continue
    }
    self.record_claude_session_usage(request_id, message)
    result.imported += 1
  }
  self.session_sync_state.set(
    file_path,
    SessionFileSyncState::new(last_modified~, last_line_offset=line_offset),
  )
  result
}

///|
async fn collect_claude_jsonl_files(projects_dir : String) -> Array[String] {
  let files : Array[String] = []
  let entries = @fsx.list_directory(projects_dir) catch { _ => return files }
  for entry in entries {
    if !(entry.kind is @fsx.FileKind::Directory) {
      continue
    }
    let project_entries = @fsx.list_directory(entry.path) catch {
      _ => continue
    }
    for project_entry in project_entries {
      if session_path_is_jsonl(project_entry.path) {
        files.push(project_entry.path)
      } else if project_entry.kind is @fsx.FileKind::Directory {
        let subagents_dir = @pathx.join(project_entry.path, "subagents")
        push_jsonl_children(subagents_dir, files)
        let workflows_dir = @pathx.join(subagents_dir, "workflows")
        let workflow_entries = @fsx.list_directory(workflows_dir) catch {
          _ => []
        }
        for workflow_entry in workflow_entries {
          if workflow_entry.kind is @fsx.FileKind::Directory {
            push_jsonl_children(workflow_entry.path, files)
          }
        }
      }
    }
  }
  files
}

///|
pub async fn TrafficStats::sync_codex_session_logs(
  self : TrafficStats,
  codex_dir? : String = default_codex_config_dir(),
) -> SessionSyncResult {
  let result = SessionSyncResult::new()
  let files = collect_codex_session_files(codex_dir)
  for file_path in files {
    result.files_scanned += 1
    try {
      let stat = @fsx.stat(file_path)
      let content = @fsx.read_file(file_path)
      let file_result = self.ingest_codex_session_jsonl(
        file_path~,
        content~,
        last_modified=stat.mtime(),
      )
      result.imported += file_result.imported
      result.skipped += file_result.skipped
      result.errors.append(file_result.errors)
    } catch {
      error =>
        result.errors.push("Codex session parse failed \{file_path}: \{error}")
    }
  }
  result
}

///|
pub fn TrafficStats::ingest_codex_session_jsonl(
  self : TrafficStats,
  file_path~ : String,
  content~ : String,
  last_modified~ : Int64,
) -> SessionSyncResult {
  let result = SessionSyncResult::new()
  result.files_scanned = 1
  let existing_state = self.session_sync_state.get(file_path)
  if existing_state is Some(state) && last_modified <= state.last_modified {
    return result
  }
  let last_offset = match existing_state {
    Some(state) => state.last_line_offset
    None => 0
  }
  let state = CodexFileParseState::{
    session_id: None,
    current_model: "unknown",
    prev_total: None,
    event_index: 0,
  }
  let mut line_offset = 0
  for line_view in content.split("\n") {
    line_offset += 1
    let line = line_view.to_owned().trim()
    if line.is_empty() {
      continue
    }
    let is_event_msg = line.contains("\"event_msg\"")
    let is_turn_context = line.contains("\"turn_context\"")
    let is_session_meta = line.contains("\"session_meta\"")
    if !is_event_msg && !is_turn_context && !is_session_meta {
      continue
    }
    if is_event_msg && !line.contains("\"token_count\"") {
      continue
    }
    let parsed = @json.parse(line) catch { _ => continue }
    guard parsed is Object(root) else { continue }
    match session_map_string(root, "type") {
      Some("session_meta") =>
        if state.session_id is None {
          match root.get("payload") {
            Some(Object(payload)) =>
              state.session_id = session_payload_id(payload)
            _ => ()
          }
        }
      Some("turn_context") =>
        match root.get("payload") {
          Some(Object(payload)) =>
            match codex_payload_model(payload) {
              Some(model) => state.current_model = normalize_codex_model(model)
              None => ()
            }
          _ => ()
        }
      Some("event_msg") =>
        match parse_codex_token_count_delta(root, state) {
          Some(delta) => {
            state.event_index += 1
            if line_offset <= last_offset || delta.is_zero() {
              continue
            }
            let session_id = state.session_id.unwrap_or("unknown")
            let request_id = "codex_session:\{session_id}:\{state.event_index}"
            let timestamp = session_map_string(root, "timestamp")
            let usage = TokenUsage::new(
              input_tokens=delta.input,
              output_tokens=delta.output,
              cache_read_tokens=delta.cached_input,
              model=Some(state.current_model),
            )
            if self.should_skip_session_insert(
                request_id,
                app_type="codex",
                model=state.current_model,
                usage~,
                created_at=session_timestamp_seconds(timestamp),
                allow_missing_cache_creation=true,
              ) {
              result.skipped += 1
            } else {
              self.record_codex_session_usage(
                request_id,
                delta,
                state.current_model,
                state.session_id,
                timestamp,
              )
              result.imported += 1
            }
          }
          None => ()
        }
      _ => ()
    }
  }
  self.session_sync_state.set(
    file_path,
    SessionFileSyncState::new(last_modified~, last_line_offset=line_offset),
  )
  result
}

///|
pub async fn TrafficStats::sync_gemini_session_logs(
  self : TrafficStats,
  gemini_dir? : String = default_gemini_dir(),
) -> SessionSyncResult {
  let result = SessionSyncResult::new()
  let files = collect_gemini_session_files(gemini_dir)
  for file_path in files {
    result.files_scanned += 1
    try {
      let stat = @fsx.stat(file_path)
      let content = @fsx.read_file(file_path)
      let file_result = self.ingest_gemini_session_json(
        file_path~,
        content~,
        last_modified=stat.mtime(),
      )
      result.imported += file_result.imported
      result.skipped += file_result.skipped
      result.errors.append(file_result.errors)
    } catch {
      error =>
        result.errors.push("Gemini session parse failed \{file_path}: \{error}")
    }
  }
  result
}

///|
pub fn TrafficStats::ingest_gemini_session_json(
  self : TrafficStats,
  file_path~ : String,
  content~ : String,
  last_modified~ : Int64,
) -> SessionSyncResult {
  let result = SessionSyncResult::new()
  result.files_scanned = 1
  let existing_state = self.session_sync_state.get(file_path)
  if existing_state is Some(state) && last_modified <= state.last_modified {
    return result
  }
  let parsed = @json.parse(content) catch {
    error => {
      result.errors.push("JSON parse failed: \{error}")
      return result
    }
  }
  guard parsed is Object(root) else { return result }
  let session_id = session_map_string(root, "sessionId")
  guard root.get("messages") is Some(Array(messages)) else {
    self.session_sync_state.set(
      file_path,
      SessionFileSyncState::new(last_modified~, last_line_offset=0),
    )
    return result
  }
  let mut gemini_message_count = 0
  for message_json in messages {
    guard message_json is Object(message) else { continue }
    guard message.get("type") is Some(String("gemini")) else { continue }
    guard message.get("tokens") is Some(Object(tokens_json)) else { continue }
    let tokens = parse_gemini_session_tokens(tokens_json)
    if tokens.is_zero() {
      continue
    }
    gemini_message_count += 1
    let message_id = session_map_string(message, "id").unwrap_or("unknown")
    let model = session_map_string(message, "model").unwrap_or("unknown")
    let timestamp = session_map_string(message, "timestamp")
    let session_id_str = session_id.unwrap_or("unknown")
    let request_id = "gemini_session:\{session_id_str}:\{message_id}"
    let output_tokens = tokens.output + tokens.thoughts
    let usage = TokenUsage::new(
      input_tokens=tokens.input,
      output_tokens~,
      cache_read_tokens=tokens.cached,
      model=Some(model),
    )
    if self.should_skip_session_insert(
        request_id,
        app_type="gemini",
        model~,
        usage~,
        created_at=session_timestamp_seconds(timestamp),
        allow_missing_cache_creation=true,
      ) {
      result.skipped += 1
    } else {
      self.record_gemini_session_usage(
        request_id, tokens, model, session_id, timestamp,
      )
      result.imported += 1
    }
  }
  self.session_sync_state.set(
    file_path,
    SessionFileSyncState::new(
      last_modified~,
      last_line_offset=gemini_message_count,
    ),
  )
  result
}

///|
async fn collect_codex_session_files(codex_dir : String) -> Array[String] {
  let files : Array[String] = []
  let sessions_dir = @pathx.join(codex_dir, "sessions")
  if @fsx.exists(sessions_dir) {
    collect_jsonl_recursive_limited(sessions_dir, files, depth=0, max_depth=3)
  }
  let archived_dir = @pathx.join(codex_dir, "archived_sessions")
  let archived_entries = @fsx.list_directory(archived_dir) catch { _ => [] }
  for entry in archived_entries {
    if session_path_is_jsonl(entry.path) {
      files.push(entry.path)
    }
  }
  files
}

///|
async fn collect_jsonl_recursive_limited(
  dir : String,
  files : Array[String],
  depth~ : Int,
  max_depth~ : Int,
) -> Unit {
  let entries = @fsx.list_directory(dir) catch { _ => return }
  for entry in entries {
    if entry.kind is @fsx.FileKind::Directory && depth < max_depth {
      collect_jsonl_recursive_limited(
        entry.path,
        files,
        depth=depth + 1,
        max_depth~,
      )
    } else if session_path_is_jsonl(entry.path) {
      files.push(entry.path)
    }
  }
}

///|
async fn collect_gemini_session_files(gemini_dir : String) -> Array[String] {
  let files : Array[String] = []
  let tmp_dir = @pathx.join(gemini_dir, "tmp")
  let project_dirs = @fsx.list_directory(tmp_dir) catch { _ => return files }
  for project_dir in project_dirs {
    if !(project_dir.kind is @fsx.FileKind::Directory) {
      continue
    }
    let chats_dir = @pathx.join(project_dir.path, "chats")
    let chat_files = @fsx.list_directory(chats_dir) catch { _ => continue }
    for file_entry in chat_files {
      let name = @pathx.basename(file_entry.path)
      if name.has_prefix("session-") && name.has_suffix(".json") {
        files.push(file_entry.path)
      }
    }
  }
  files
}

///|
async fn push_jsonl_children(dir : String, files : Array[String]) -> Unit {
  let entries = @fsx.list_directory(dir) catch { _ => return }
  for entry in entries {
    if session_path_is_jsonl(entry.path) {
      files.push(entry.path)
    }
  }
}

///|
fn session_path_is_jsonl(path : String) -> Bool {
  path.has_suffix(".jsonl")
}

///|
fn normalize_codex_model(raw : String) -> String {
  let mut name = raw.trim().to_lower().to_owned()
  if name.rev_find("/") is Some(index) {
    name = name[index + 1:].to_owned()
  }
  match strip_codex_model_date_suffix(name) {
    Some(stripped) => stripped
    None => name
  }
}

///|
fn strip_codex_model_date_suffix(model_id : String) -> String? {
  if model_id.length() > 11 {
    let start = model_id.length() - 11
    let suffix = model_id[start:].to_owned()
    if suffix.length() == 11 &&
      suffix[0] == '-' &&
      session_ascii_digits(suffix[1:5].to_owned()) &&
      suffix[5] == '-' &&
      session_ascii_digits(suffix[6:8].to_owned()) &&
      suffix[8] == '-' &&
      session_ascii_digits(suffix[9:11].to_owned()) {
      return Some(model_id[:start].to_owned())
    }
  }
  guard model_id.rev_find("-") is Some(index) else { return None }
  let base = model_id[:index].to_owned()
  let suffix = model_id[index + 1:].to_owned()
  if !base.is_empty() && suffix.length() == 8 && session_ascii_digits(suffix) {
    Some(base)
  } else {
    None
  }
}

///|
fn parse_codex_token_count_delta(
  root : Map[String, Json],
  state : CodexFileParseState,
) -> DeltaSessionTokens? {
  guard root.get("payload") is Some(Object(payload)) else { return None }
  guard payload.get("type") is Some(String("token_count")) else { return None }
  guard payload.get("info") is Some(Object(info)) else { return None }
  match codex_info_model(info, payload) {
    Some(model) => state.current_model = normalize_codex_model(model)
    None => ()
  }
  let (cumulative, is_total) = match info.get("total_token_usage") {
    Some(Object(total)) => (parse_cumulative_session_tokens(total), true)
    _ =>
      match info.get("last_token_usage") {
        Some(Object(last)) => (parse_cumulative_session_tokens(last), false)
        _ => return None
      }
  }
  guard cumulative is Some(current) else { return None }
  let delta = if is_total {
    let computed = compute_delta_session_tokens(state.prev_total, current)
    state.prev_total = Some(current)
    computed
  } else {
    DeltaSessionTokens::{
      input: current.input,
      cached_input: current.cached_input,
      output: current.output,
    }
  }
  Some(DeltaSessionTokens::{
    input: delta.input,
    cached_input: session_min_int(delta.cached_input, delta.input),
    output: delta.output,
  })
}

///|
fn parse_cumulative_session_tokens(
  obj : Map[String, Json],
) -> CumulativeSessionTokens? {
  Some(CumulativeSessionTokens::{
    input: json_int_or_zero(obj, "input_tokens"),
    cached_input: match json_int(obj, "cached_input_tokens") {
      Some(value) => value
      None => json_int_or_zero(obj, "cache_read_input_tokens")
    },
    output: json_int_or_zero(obj, "output_tokens"),
  })
}

///|
fn compute_delta_session_tokens(
  prev : CumulativeSessionTokens?,
  current : CumulativeSessionTokens,
) -> DeltaSessionTokens {
  match prev {
    None =>
      DeltaSessionTokens::{
        input: current.input,
        cached_input: current.cached_input,
        output: current.output,
      }
    Some(old) =>
      DeltaSessionTokens::{
        input: max_int(current.input - old.input, 0),
        cached_input: max_int(current.cached_input - old.cached_input, 0),
        output: max_int(current.output - old.output, 0),
      }
  }
}

///|
fn DeltaSessionTokens::is_zero(self : DeltaSessionTokens) -> Bool {
  self.input == 0 && self.cached_input == 0 && self.output == 0
}

///|
fn codex_payload_model(payload : Map[String, Json]) -> String? {
  match session_map_string(payload, "model") {
    Some(model) => Some(model)
    None =>
      match payload.get("info") {
        Some(Object(info)) => session_map_string(info, "model")
        _ => None
      }
  }
}

///|
fn codex_info_model(
  info : Map[String, Json],
  payload : Map[String, Json],
) -> String? {
  match session_map_string(info, "model") {
    Some(model) => Some(model)
    None =>
      match session_map_string(info, "model_name") {
        Some(model) => Some(model)
        None => session_map_string(payload, "model")
      }
  }
}

///|
fn session_payload_id(payload : Map[String, Json]) -> String? {
  match session_map_string(payload, "session_id") {
    Some(id) => Some(id)
    None =>
      match session_map_string(payload, "sessionId") {
        Some(id) => Some(id)
        None => session_map_string(payload, "id")
      }
  }
}

///|
fn parse_gemini_session_tokens(
  tokens : Map[String, Json],
) -> GeminiSessionTokens {
  GeminiSessionTokens::{
    input: json_int_or_zero(tokens, "input"),
    output: json_int_or_zero(tokens, "output"),
    cached: json_int_or_zero(tokens, "cached"),
    thoughts: json_int_or_zero(tokens, "thoughts"),
  }
}

///|
fn GeminiSessionTokens::is_zero(self : GeminiSessionTokens) -> Bool {
  self.input == 0 && self.output == 0 && self.cached == 0 && self.thoughts == 0
}

///|
fn should_replace_claude_session_usage(
  existing : ParsedClaudeSessionUsage?,
  candidate : ParsedClaudeSessionUsage,
) -> Bool {
  match existing {
    None => true
    Some(old) =>
      if candidate.stop_reason is Some(_) && old.stop_reason is None {
        true
      } else if (candidate.stop_reason is Some(_)) ==
        (old.stop_reason is Some(_)) {
        candidate.usage.output_tokens > old.usage.output_tokens
      } else {
        false
      }
  }
}

///|
fn TrafficStats::record_claude_session_usage(
  self : TrafficStats,
  request_id : String,
  message : ParsedClaudeSessionUsage,
) -> Unit {
  let usage = message.usage
  let pricing = find_static_model_pricing(message.model)
  let cost = match pricing {
    Some(model_pricing) =>
      calculate_cost_for_app("claude", usage, model_pricing)
    None =>
      {
        input_cost_usd: "0",
        output_cost_usd: "0",
        cache_read_cost_usd: "0",
        cache_creation_cost_usd: "0",
        total_cost_usd: "0",
      }
  }
  self.record_request_log(
    RequestLog::new(
      request_id~,
      provider_id="_session",
      app_type="claude",
      model=message.model,
      request_model=Some(message.model),
      pricing_model=Some(message.model),
      usage~,
      input_cost_usd=cost.input_cost_usd,
      output_cost_usd=cost.output_cost_usd,
      cache_read_cost_usd=cost.cache_read_cost_usd,
      cache_creation_cost_usd=cost.cache_creation_cost_usd,
      total_cost_usd=cost.total_cost_usd,
      latency_ms=0,
      status_code=200,
      session_id=message.session_id,
      provider_type=Some("session_log"),
      is_streaming=true,
      cost_multiplier="1.0",
      created_at=session_timestamp_seconds(message.timestamp),
      data_source="session_log",
    ),
  )
}

///|
fn TrafficStats::record_codex_session_usage(
  self : TrafficStats,
  request_id : String,
  delta : DeltaSessionTokens,
  model : String,
  session_id : String?,
  timestamp : String?,
) -> Unit {
  let usage = TokenUsage::new(
    input_tokens=delta.input,
    output_tokens=delta.output,
    cache_read_tokens=delta.cached_input,
    model=Some(model),
  )
  let pricing = find_static_model_pricing(model)
  let cost = match pricing {
    Some(model_pricing) => calculate_cost_for_app("codex", usage, model_pricing)
    None =>
      {
        input_cost_usd: "0",
        output_cost_usd: "0",
        cache_read_cost_usd: "0",
        cache_creation_cost_usd: "0",
        total_cost_usd: "0",
      }
  }
  self.record_request_log(
    RequestLog::new(
      request_id~,
      provider_id="_codex_session",
      app_type="codex",
      model~,
      request_model=Some(model),
      pricing_model=Some(model),
      usage~,
      input_cost_usd=cost.input_cost_usd,
      output_cost_usd=cost.output_cost_usd,
      cache_read_cost_usd=cost.cache_read_cost_usd,
      cache_creation_cost_usd=cost.cache_creation_cost_usd,
      total_cost_usd=cost.total_cost_usd,
      latency_ms=0,
      status_code=200,
      session_id~,
      provider_type=Some("codex_session"),
      is_streaming=true,
      cost_multiplier="1.0",
      created_at=session_timestamp_seconds(timestamp),
      data_source="codex_session",
    ),
  )
}

///|
fn TrafficStats::record_gemini_session_usage(
  self : TrafficStats,
  request_id : String,
  tokens : GeminiSessionTokens,
  model : String,
  session_id : String?,
  timestamp : String?,
) -> Unit {
  let output_tokens = tokens.output + tokens.thoughts
  let usage = TokenUsage::new(
    input_tokens=tokens.input,
    output_tokens~,
    cache_read_tokens=tokens.cached,
    model=Some(model),
  )
  let pricing = find_static_model_pricing(model)
  let cost = match pricing {
    Some(model_pricing) =>
      calculate_cost_for_app("gemini", usage, model_pricing)
    None =>
      {
        input_cost_usd: "0",
        output_cost_usd: "0",
        cache_read_cost_usd: "0",
        cache_creation_cost_usd: "0",
        total_cost_usd: "0",
      }
  }
  self.record_request_log(
    RequestLog::new(
      request_id~,
      provider_id="_gemini_session",
      app_type="gemini",
      model~,
      request_model=Some(model),
      pricing_model=Some(model),
      usage~,
      input_cost_usd=cost.input_cost_usd,
      output_cost_usd=cost.output_cost_usd,
      cache_read_cost_usd=cost.cache_read_cost_usd,
      cache_creation_cost_usd=cost.cache_creation_cost_usd,
      total_cost_usd=cost.total_cost_usd,
      latency_ms=0,
      status_code=200,
      session_id~,
      provider_type=Some("gemini_session"),
      is_streaming=true,
      cost_multiplier="1.0",
      created_at=session_timestamp_seconds(timestamp),
      data_source="gemini_session",
    ),
  )
}

///|
fn TrafficStats::should_skip_session_insert(
  self : TrafficStats,
  request_id : String,
  app_type~ : String,
  model~ : String,
  usage~ : TokenUsage,
  created_at~ : Int,
  allow_missing_cache_creation? : Bool = false,
) -> Bool {
  for log in self.request_logs {
    if log.request_id == request_id {
      return true
    }
    let cache_creation_matches = log.cache_creation_tokens ==
      usage.cache_creation_tokens ||
      allow_missing_cache_creation
    if log.data_source == "proxy" &&
      log.status_code >= 200 &&
      log.status_code < 300 &&
      log.app_type == app_type &&
      session_models_match(log.model, model) &&
      log.input_tokens == usage.input_tokens &&
      log.output_tokens == usage.output_tokens &&
      log.cache_read_tokens == usage.cache_read_tokens &&
      cache_creation_matches &&
      session_abs_int(log.created_at - created_at) <=
      SESSION_PROXY_DEDUP_WINDOW_SECONDS {
      return true
    }
  }
  false
}

///|
fn session_timestamp_seconds(timestamp : String?) -> Int {
  match timestamp {
    Some(value) =>
      parse_session_timestamp_seconds(value).unwrap_or(
        @async.now().to_int() / 1000,
      )
    None => @async.now().to_int() / 1000
  }
}

///|
fn parse_session_timestamp_seconds(timestamp : String) -> Int? {
  if timestamp.length() < 19 {
    return None
  }
  guard parse_fixed_int(timestamp, 0, 4) is Some(year) else { return None }
  guard parse_fixed_int(timestamp, 5, 7) is Some(month) else { return None }
  guard parse_fixed_int(timestamp, 8, 10) is Some(day) else { return None }
  guard parse_fixed_int(timestamp, 11, 13) is Some(hour) else { return None }
  guard parse_fixed_int(timestamp, 14, 16) is Some(minute) else { return None }
  guard parse_fixed_int(timestamp, 17, 19) is Some(second) else { return None }
  let offset_seconds = parse_timestamp_offset_seconds(timestamp).unwrap_or(0)
  let days = days_from_civil(year, month, day)
  Some(days * 86400 + hour * 3600 + minute * 60 + second - offset_seconds)
}

///|
fn parse_fixed_int(text : String, start : Int, end : Int) -> Int? {
  if text.length() < end {
    return None
  }
  try @string.parse_int(text[start:end], base=10) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn parse_timestamp_offset_seconds(timestamp : String) -> Int? {
  if timestamp.length() <= 19 {
    return Some(0)
  }
  if timestamp.has_suffix("Z") {
    return Some(0)
  }
  let mut offset_start = -1
  let mut i = 19
  while i < timestamp.length() {
    let ch = timestamp[i]
    if ch == '+' || ch == '-' {
      offset_start = i
    }
    i += 1
  }
  if offset_start < 0 || timestamp.length() < offset_start + 6 {
    return Some(0)
  }
  let sign = if timestamp[offset_start] == '-' { -1 } else { 1 }
  guard parse_fixed_int(timestamp, offset_start + 1, offset_start + 3)
    is Some(hours) else {
    return None
  }
  guard parse_fixed_int(timestamp, offset_start + 4, offset_start + 6)
    is Some(minutes) else {
    return None
  }
  Some(sign * (hours * 3600 + minutes * 60))
}

///|
fn days_from_civil(year : Int, month : Int, day : Int) -> Int {
  let mut y = year
  let m = month
  let year_shift = if m <= 2 { 1 } else { 0 }
  y -= year_shift
  let era = floor_div_int(y, 400)
  let yoe = y - era * 400
  let month_shift = if m > 2 { -3 } else { 9 }
  let mp = m + month_shift
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
fn session_json_string(json : Json, key : String) -> String? {
  match json {
    Object(obj) => session_map_string(obj, key)
    _ => None
  }
}

///|
fn session_map_string(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn session_models_match(log_model : String, session_model : String) -> Bool {
  log_model.to_lower() == session_model.to_lower() ||
  log_model.to_lower() == "unknown" ||
  session_model.to_lower() == "unknown"
}

///|
fn session_abs_int(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
fn session_min_int(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn session_ascii_digits(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for ch in value {
    let code = ch.to_int()
    if code < '0'.to_int() || code > '9'.to_int() {
      return false
    }
  }
  true
}
