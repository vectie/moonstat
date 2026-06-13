///|
const CLAUDE_SESSION_REQUEST_ID_PREFIX : String = "session:"

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
    if self.should_skip_session_request(request_id, message) {
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
fn TrafficStats::should_skip_session_request(
  self : TrafficStats,
  request_id : String,
  message : ParsedClaudeSessionUsage,
) -> Bool {
  for log in self.request_logs {
    if log.request_id == request_id {
      return true
    }
    if log.data_source == "session_log" &&
      log.app_type == "claude" &&
      log.model == message.model &&
      log.input_tokens == message.usage.input_tokens &&
      log.output_tokens == message.usage.output_tokens &&
      log.cache_read_tokens == message.usage.cache_read_tokens &&
      log.cache_creation_tokens == message.usage.cache_creation_tokens &&
      log.created_at == session_timestamp_seconds(message.timestamp) {
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
