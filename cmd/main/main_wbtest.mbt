///|
test "has flag matches exact CLI option" {
  let args = ["moonstat", "models", "fetch", "--full-url"]
  assert_true(has_flag(args, "--full-url"))
  assert_false(has_flag(args, "--is-full-url"))
}

///|
test "provider model JSON uses ccs field names" {
  let json = provider_model_fields_to_json("gpt-test", Some("openai"))
  assert_eq(json.stringify(), "{\"id\":\"gpt-test\",\"ownedBy\":\"openai\"}")
}

///|
test "usage sync path accepts standalone projects dir override" {
  assert_eq(
    usage_sync_path(["moonstat", "usage", "sync"]),
    "/usage/sync-session",
  )
  assert_eq(
    usage_sync_path([
      "moonstat", "usage", "sync", "--projects-dir", "/tmp/claude/projects",
    ]),
    "/usage/sync-session?projects_dir=/tmp/claude/projects",
  )
}
