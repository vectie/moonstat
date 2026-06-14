///|
fn ccs_sync_default_remote_root() -> String {
  "cc-switch-sync"
}

///|
fn ccs_sync_default_profile() -> String {
  "default"
}

///|
fn ccs_sync_default_status_json() -> Json {
  Json::object({})
}

///|
fn ccs_sync_status_json(incoming : Map[String, Json], existing : Json?) -> Json {
  match existing {
    Some(Object(existing_obj)) =>
      match existing_obj.get("status") {
        Some(Object(status)) => return Json::object(status)
        _ => ()
      }
    _ => ()
  }
  match incoming.get("status") {
    Some(Object(status)) => Json::object(status)
    _ => ccs_sync_default_status_json()
  }
}

///|
fn ccs_sync_json_string(
  obj : Map[String, Json],
  keys : Array[String],
) -> String {
  json_string_from_map_any(obj, keys).unwrap_or("").trim().to_owned()
}

///|
fn ccs_sync_json_bool(obj : Map[String, Json], keys : Array[String]) -> Bool {
  json_bool_from_map_any(obj, keys).unwrap_or(false)
}

///|
fn ccs_sync_secret_or_existing(
  obj : Map[String, Json],
  keys : Array[String],
  existing : Json?,
  preserve_empty : Bool,
) -> String {
  let incoming = ccs_sync_json_string(obj, keys)
  if !preserve_empty || !incoming.is_empty() {
    return incoming
  }
  match existing {
    Some(Object(existing_obj)) =>
      json_string_from_map_any(existing_obj, keys).unwrap_or("")
    _ => incoming
  }
}

///|
fn ccs_webdav_sync_settings_json(
  settings : Json,
  existing : Json?,
  preserve_empty_password : Bool,
) -> Json {
  guard settings is Object(obj) else {
    return ccs_webdav_sync_empty_settings_json()
  }
  let remote_root = ccs_sync_json_string(obj, ["remoteRoot", "remote_root"])
  let profile = ccs_sync_json_string(obj, ["profile"])
  {
    "enabled": Json::boolean(ccs_sync_json_bool(obj, ["enabled"])),
    "autoSync": Json::boolean(
      ccs_sync_json_bool(obj, ["autoSync", "auto_sync"]),
    ),
    "baseUrl": Json::string(ccs_sync_json_string(obj, ["baseUrl", "base_url"])),
    "username": Json::string(ccs_sync_json_string(obj, ["username"])),
    "password": Json::string(
      ccs_sync_secret_or_existing(
        obj,
        ["password"],
        existing,
        preserve_empty_password,
      ),
    ),
    "remoteRoot": Json::string(
      if remote_root.is_empty() {
        ccs_sync_default_remote_root()
      } else {
        remote_root
      },
    ),
    "profile": Json::string(
      if profile.is_empty() {
        ccs_sync_default_profile()
      } else {
        profile
      },
    ),
    "status": ccs_sync_status_json(obj, existing),
  }.to_json()
}

///|
fn ccs_webdav_sync_empty_settings_json() -> Json {
  {
    "enabled": Json::boolean(false),
    "autoSync": Json::boolean(false),
    "baseUrl": Json::string(""),
    "username": Json::string(""),
    "password": Json::string(""),
    "remoteRoot": Json::string(ccs_sync_default_remote_root()),
    "profile": Json::string(ccs_sync_default_profile()),
    "status": ccs_sync_default_status_json(),
  }.to_json()
}

///|
fn ccs_webdav_sync_settings_empty(settings : Json) -> Bool {
  guard settings is Object(obj) else { return true }
  ccs_sync_json_string(obj, ["baseUrl", "base_url"]).is_empty() &&
  ccs_sync_json_string(obj, ["username"]).is_empty() &&
  ccs_sync_json_string(obj, ["password"]).is_empty()
}

///|
fn ccs_validate_webdav_sync_settings(settings : Json) -> String? {
  guard settings is Object(obj) else { return Some("WebDAV URL is required.") }
  if ccs_sync_json_string(obj, ["baseUrl", "base_url"]).is_empty() {
    return Some("WebDAV URL is required.")
  }
  if ccs_sync_json_string(obj, ["username"]).is_empty() {
    return Some("WebDAV username is required.")
  }
  None
}

///|
fn ccs_s3_sync_settings_json(
  settings : Json,
  existing : Json?,
  preserve_empty_secret : Bool,
) -> Json {
  guard settings is Object(obj) else {
    return ccs_s3_sync_empty_settings_json()
  }
  let remote_root = ccs_sync_json_string(obj, ["remoteRoot", "remote_root"])
  let profile = ccs_sync_json_string(obj, ["profile"])
  {
    "enabled": Json::boolean(ccs_sync_json_bool(obj, ["enabled"])),
    "autoSync": Json::boolean(
      ccs_sync_json_bool(obj, ["autoSync", "auto_sync"]),
    ),
    "region": Json::string(ccs_sync_json_string(obj, ["region"])),
    "bucket": Json::string(ccs_sync_json_string(obj, ["bucket"])),
    "accessKeyId": Json::string(
      ccs_sync_json_string(obj, ["accessKeyId", "access_key_id"]),
    ),
    "secretAccessKey": Json::string(
      ccs_sync_secret_or_existing(
        obj,
        ["secretAccessKey", "secret_access_key"],
        existing,
        preserve_empty_secret,
      ),
    ),
    "endpoint": Json::string(ccs_sync_json_string(obj, ["endpoint"])),
    "remoteRoot": Json::string(
      if remote_root.is_empty() {
        ccs_sync_default_remote_root()
      } else {
        remote_root
      },
    ),
    "profile": Json::string(
      if profile.is_empty() {
        ccs_sync_default_profile()
      } else {
        profile
      },
    ),
    "status": ccs_sync_status_json(obj, existing),
  }.to_json()
}

///|
fn ccs_s3_sync_empty_settings_json() -> Json {
  {
    "enabled": Json::boolean(false),
    "autoSync": Json::boolean(false),
    "region": Json::string(""),
    "bucket": Json::string(""),
    "accessKeyId": Json::string(""),
    "secretAccessKey": Json::string(""),
    "endpoint": Json::string(""),
    "remoteRoot": Json::string(ccs_sync_default_remote_root()),
    "profile": Json::string(ccs_sync_default_profile()),
    "status": ccs_sync_default_status_json(),
  }.to_json()
}

///|
fn ccs_s3_sync_settings_empty(settings : Json) -> Bool {
  guard settings is Object(obj) else { return true }
  ccs_sync_json_string(obj, ["bucket"]).is_empty() &&
  ccs_sync_json_string(obj, ["region"]).is_empty() &&
  ccs_sync_json_string(obj, ["accessKeyId", "access_key_id"]).is_empty() &&
  ccs_sync_json_string(obj, ["secretAccessKey", "secret_access_key"]).is_empty()
}

///|
fn ccs_validate_s3_sync_settings(settings : Json) -> String? {
  guard settings is Object(obj) else { return Some("S3 bucket is required.") }
  if ccs_sync_json_string(obj, ["bucket"]).is_empty() {
    return Some("S3 bucket is required.")
  }
  if ccs_sync_json_string(obj, ["region"]).is_empty() {
    return Some("S3 region is required.")
  }
  if ccs_sync_json_string(obj, ["accessKeyId", "access_key_id"]).is_empty() {
    return Some("S3 Access Key ID is required.")
  }
  if ccs_sync_json_string(obj, ["secretAccessKey", "secret_access_key"]).is_empty() {
    return Some("S3 Secret Access Key is required.")
  }
  None
}

///|
fn ccs_app_webdav_sync_json(settings : Json) -> Json? {
  guard settings is Object(obj) else { return None }
  match obj.get("webdavSync") {
    Some(value) => Some(value)
    None => obj.get("webdav_sync")
  }
}

///|
fn ccs_app_s3_sync_json(settings : Json) -> Json? {
  guard settings is Object(obj) else { return None }
  match obj.get("s3Sync") {
    Some(value) => Some(value)
    None => obj.get("s3_sync")
  }
}

///|
fn ccs_app_settings_with_sync(
  settings : Json,
  key : String,
  sync_settings : Json,
) -> Json {
  match settings {
    Object(obj) => {
      obj[key] = sync_settings
      Json::object(obj)
    }
    _ => {
      let obj : Map[String, Json] = {}
      obj[key] = sync_settings
      Json::object(obj)
    }
  }
}

///|
fn ccs_sync_settings_request(path : StringView, body : Json?) -> Json? {
  match ccs_json_request(path, body, ["settings", "config"]) {
    Some(value) => Some(value)
    None => body
  }
}

///|
fn ccs_sync_preserve_empty_password_request(
  path : StringView,
  body : Json?,
) -> Bool {
  proxy_bool_request(path, body, [
    "preserveEmptyPassword", "preserve_empty_password",
  ]).unwrap_or(true)
}

///|
fn ccs_sync_password_touched_request(path : StringView, body : Json?) -> Bool {
  proxy_bool_request(path, body, ["passwordTouched", "password_touched"]).unwrap_or(
    false,
  )
}

///|
fn ccs_webdav_sync_required_error(settings : Json) -> String? {
  match ccs_app_webdav_sync_json(settings) {
    None => Some("WebDAV sync is not configured.")
    Some(raw) => {
      let normalized = ccs_webdav_sync_settings_json(raw, None, false)
      if ccs_webdav_sync_settings_empty(normalized) {
        return Some("WebDAV sync is not configured.")
      }
      guard normalized is Object(obj) else {
        return Some("WebDAV sync is not configured.")
      }
      if !ccs_sync_json_bool(obj, ["enabled"]) {
        return Some("WebDAV sync is disabled.")
      }
      ccs_validate_webdav_sync_settings(normalized)
    }
  }
}

///|
fn ccs_s3_sync_required_error(settings : Json) -> String? {
  match ccs_app_s3_sync_json(settings) {
    None => Some("S3 sync is not configured.")
    Some(raw) => {
      let normalized = ccs_s3_sync_settings_json(raw, None, false)
      if ccs_s3_sync_settings_empty(normalized) {
        return Some("S3 sync is not configured.")
      }
      guard normalized is Object(obj) else {
        return Some("S3 sync is not configured.")
      }
      if !ccs_sync_json_bool(obj, ["enabled"]) {
        return Some("S3 sync is disabled.")
      }
      ccs_validate_s3_sync_settings(normalized)
    }
  }
}
