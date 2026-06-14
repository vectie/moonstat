///|
const CCS_UPDATE_URL = "https://github.com/farion1231/cc-switch/releases/latest"

///|
const CCS_TOOL_VERSION_TIMEOUT_MS = 3000

///|
fn ccs_normalize_external_url(url : String) -> String {
  let trimmed = url.trim().to_owned()
  let lower = trimmed.to_lower()
  if lower.find("http://") == Some(0) || lower.find("https://") == Some(0) {
    trimmed
  } else {
    "https://\{trimmed}"
  }
}

///|
fn ccs_tool_names() -> Array[String] {
  ["claude", "codex", "gemini", "opencode", "openclaw", "hermes"]
}

///|
fn ccs_requested_tool_names(raw : String?) -> Array[String] {
  let valid = ccs_tool_names()
  let requested : Array[String] = []
  match raw {
    Some(value) =>
      for part_view in value.split(",") {
        let name = part_view.to_owned().trim().to_lower().to_owned()
        if !name.is_empty() && valid.contains(name) && !requested.contains(name) {
          requested.push(name)
        }
      }
    None => ()
  }
  if requested.is_empty() {
    valid
  } else {
    requested
  }
}

///|
fn ccs_update_url() -> String {
  CCS_UPDATE_URL
}

///|
fn ccs_init_error_json() -> Json {
  Json::null()
}

///|
fn ccs_migration_result_json() -> Json {
  Json::boolean(false)
}

///|
fn ccs_skills_migration_result_json() -> Json {
  Json::null()
}

///|
fn ccs_dialog_result_json() -> Json {
  Json::null()
}

///|
async fn ccs_portable_mode() -> Bool {
  let exe = @os.executable() catch { _ => return false }
  let marker = @pathx.join(@pathx.dirname(exe), "portable.ini")
  @fsx.exists_as_file(marker) catch {
    _ => false
  }
}

///|
async fn ccs_get_tool_versions_json(tools : String?) -> Json {
  let versions : Array[Json] = []
  for tool in ccs_requested_tool_names(tools) {
    versions.push(ccs_single_tool_version_json(tool))
  }
  Json::array(versions)
}

///|
async fn ccs_single_tool_version_json(tool : String) -> Json {
  let result = @spawn.spawn(
    tool,
    ["--version"],
    timeout=CCS_TOOL_VERSION_TIMEOUT_MS,
  ) catch {
    err =>
      return ccs_tool_version_json(
        tool,
        None,
        None,
        Some(err.to_string()),
        false,
      )
  }
  let combined = if result.stdout.trim().is_empty() {
    result.stderr
  } else {
    result.stdout
  }
  let version = ccs_first_output_line(combined)
  let broken = result.status != 0
  ccs_tool_version_json(
    tool,
    version,
    None,
    if broken {
      Some(result.stderr.trim().to_owned())
    } else {
      None
    },
    broken,
  )
}

///|
fn ccs_first_output_line(output : String) -> String? {
  for line_view in output.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    if !line.is_empty() {
      return Some(line)
    }
  }
  None
}

///|
fn ccs_tool_version_json(
  name : String,
  version : String?,
  latest_version : String?,
  error : String?,
  installed_but_broken : Bool,
) -> Json {
  {
    "name": Json::string(name),
    "version": match version {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "latest_version": match latest_version {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "error": match error {
      Some(value) if !value.is_empty() => Json::string(value)
      _ => Json::null()
    },
    "installed_but_broken": Json::boolean(installed_but_broken),
    "env_type": Json::string("macos"),
    "wsl_distro": Json::null(),
  }.to_json()
}
