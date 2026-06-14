///|
test "ccs webdav sync settings normalize and preserve password" {
  let existing = {
    "enabled": Json::boolean(true),
    "baseUrl": Json::string("https://dav.example.com"),
    "username": Json::string("alice"),
    "password": Json::string("secret"),
    "status": { "lastError": Json::string("previous") }.to_json(),
  }.to_json()
  let incoming = {
    "enabled": Json::boolean(true),
    "auto_sync": Json::boolean(true),
    "base_url": Json::string(" https://dav.example.com/root "),
    "username": Json::string(" alice "),
    "password": Json::string(""),
    "remote_root": Json::string(""),
    "profile": Json::string(""),
  }.to_json()
  guard ccs_webdav_sync_settings_json(incoming, Some(existing), true)
    is Object(obj) else {
    fail("expected webdav settings object")
  }
  assert_eq(
    json_string_from_map(obj, "baseUrl"),
    Some("https://dav.example.com/root"),
  )
  assert_eq(json_string_from_map(obj, "username"), Some("alice"))
  assert_eq(json_string_from_map(obj, "password"), Some("secret"))
  assert_eq(json_string_from_map(obj, "remoteRoot"), Some("cc-switch-sync"))
  assert_eq(json_string_from_map(obj, "profile"), Some("default"))
  guard obj.get("status") is Some(Object(status)) else {
    fail("expected preserved status")
  }
  assert_eq(json_string_from_map(status, "lastError"), Some("previous"))
  assert_eq(ccs_validate_webdav_sync_settings(Json::object(obj)), None)
}

///|
test "ccs webdav sync validation and guard messages match ccs" {
  assert_eq(
    ccs_validate_webdav_sync_settings(
      { "username": Json::string("alice") }.to_json(),
    ),
    Some("WebDAV URL is required."),
  )
  let settings = {
    "webdavSync": {
      "enabled": Json::boolean(false),
      "baseUrl": Json::string("https://dav.example.com"),
      "username": Json::string("alice"),
    }.to_json(),
  }.to_json()
  assert_eq(
    ccs_webdav_sync_required_error(settings),
    Some("WebDAV sync is disabled."),
  )
  assert_eq(
    ccs_webdav_sync_required_error(Json::object({})),
    Some("WebDAV sync is not configured."),
  )
}

///|
test "ccs s3 sync settings normalize and preserve secret" {
  let existing = {
    "secretAccessKey": Json::string("SECRET"),
    "status": { "lastRemoteEtag": Json::string("etag-1") }.to_json(),
  }.to_json()
  let incoming = {
    "enabled": Json::boolean(true),
    "autoSync": Json::boolean(true),
    "region": Json::string(" us-east-1 "),
    "bucket": Json::string(" moonstat "),
    "access_key_id": Json::string(" AKID "),
    "secret_access_key": Json::string(""),
    "endpoint": Json::string(" https://s3.example.com "),
    "remoteRoot": Json::string(""),
  }.to_json()
  guard ccs_s3_sync_settings_json(incoming, Some(existing), true) is Object(obj) else {
    fail("expected s3 settings object")
  }
  assert_eq(json_string_from_map(obj, "region"), Some("us-east-1"))
  assert_eq(json_string_from_map(obj, "bucket"), Some("moonstat"))
  assert_eq(json_string_from_map(obj, "accessKeyId"), Some("AKID"))
  assert_eq(json_string_from_map(obj, "secretAccessKey"), Some("SECRET"))
  assert_eq(
    json_string_from_map(obj, "endpoint"),
    Some("https://s3.example.com"),
  )
  assert_eq(json_string_from_map(obj, "remoteRoot"), Some("cc-switch-sync"))
  guard obj.get("status") is Some(Object(status)) else {
    fail("expected preserved status")
  }
  assert_eq(json_string_from_map(status, "lastRemoteEtag"), Some("etag-1"))
  assert_eq(ccs_validate_s3_sync_settings(Json::object(obj)), None)
}

///|
test "ccs s3 sync validation and guard messages match ccs" {
  assert_eq(
    ccs_validate_s3_sync_settings(
      { "region": Json::string("us-east-1") }.to_json(),
    ),
    Some("S3 bucket is required."),
  )
  assert_eq(
    ccs_validate_s3_sync_settings(
      {
        "bucket": Json::string("moonstat"),
        "region": Json::string("us-east-1"),
        "accessKeyId": Json::string("AKID"),
      }.to_json(),
    ),
    Some("S3 Secret Access Key is required."),
  )
  let settings = {
    "s3Sync": {
      "enabled": Json::boolean(false),
      "bucket": Json::string("moonstat"),
      "region": Json::string("us-east-1"),
      "accessKeyId": Json::string("AKID"),
      "secretAccessKey": Json::string("SECRET"),
    }.to_json(),
  }.to_json()
  assert_eq(ccs_s3_sync_required_error(settings), Some("S3 sync is disabled."))
  assert_eq(
    ccs_s3_sync_required_error(Json::object({})),
    Some("S3 sync is not configured."),
  )
}
