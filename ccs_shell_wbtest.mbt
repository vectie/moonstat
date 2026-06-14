///|
test "ccs external url normalization mirrors shell command behavior" {
  assert_eq(
    ccs_normalize_external_url("github.com/farion1231/cc-switch"),
    "https://github.com/farion1231/cc-switch",
  )
  assert_eq(
    ccs_normalize_external_url("https://github.com/farion1231/cc-switch"),
    "https://github.com/farion1231/cc-switch",
  )
}

///|
test "ccs requested tool names keeps valid unique tools" {
  assert_eq(ccs_requested_tool_names(Some("codex,unknown,codex,claude")), [
    "codex", "claude",
  ])
  assert_eq(ccs_requested_tool_names(Some("unknown")), ccs_tool_names())
}

///|
test "ccs standalone app shell defaults use tauri-compatible empty results" {
  assert_eq(ccs_init_error_json(), Json::null())
  assert_eq(ccs_migration_result_json(), Json::boolean(false))
  assert_eq(ccs_skills_migration_result_json(), Json::null())
  assert_eq(ccs_dialog_result_json(), Json::null())
}
