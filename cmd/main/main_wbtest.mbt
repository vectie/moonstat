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
      "moonstat", "usage", "sync", "--projects-dir", "/tmp/claude/projects", "--codex-dir",
      "/tmp/codex", "--gemini-dir", "/tmp/gemini", "--opencode-export-path", "/tmp/opencode/messages.jsonl",
      "--opencode-db-path", "/tmp/opencode/opencode.db",
    ]),
    "/usage/sync-session?projects_dir=/tmp/claude/projects&codex_dir=/tmp/codex&gemini_dir=/tmp/gemini&opencode_export_path=/tmp/opencode/messages.jsonl&opencode_db_path=/tmp/opencode/opencode.db",
  )
}

///|
test "usage pricing paths accept ccs editable pricing args" {
  assert_eq(
    usage_pricing_update_path([
      "moonstat", "usage", "pricing", "set", "--model-id", "custom", "--display-name",
      "Custom", "--input-cost", "1", "--output-cost", "2", "--cache-read-cost", "0.1",
      "--cache-creation-cost", "0",
    ]),
    Some(
      "/usage/model-pricing?model_id=custom&display_name=Custom&input_cost=1&output_cost=2&cache_read_cost=0.1&cache_creation_cost=0",
    ),
  )
  assert_eq(
    usage_pricing_delete_path([
      "moonstat", "usage", "pricing", "delete", "--model-id", "custom",
    ]),
    Some("/usage/model-pricing?model_id=custom"),
  )
  assert_eq(
    usage_pricing_update_path([
      "moonstat", "usage", "pricing", "set", "--model-id", "custom",
    ]),
    None,
  )
}
