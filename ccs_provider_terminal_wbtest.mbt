///|
test "ccs provider terminal env extracts app-specific fields" {
  let provider = ProviderRouteTarget::new(
    app_type="codex",
    provider_id="p1",
    provider_name="Provider",
    base_url=Some("https://api.example.test/v1"),
    api_key=Some("sk-test"),
    settings_config=Some(
      {
        "auth": Json::string("sk-auth"),
        "env": Json::object({ "EXTRA_FLAG": Json::string("1") }),
      }.to_json(),
    ),
  )
  let env = ccs_provider_terminal_env(provider, "codex")
  assert_eq(env["OPENAI_API_KEY"], "sk-test")
  assert_eq(env["OPENAI_BASE_URL"], "https://api.example.test/v1")
  assert_eq(env["EXTRA_FLAG"], "1")
}

///|
test "ccs provider terminal command quotes cwd and env values" {
  let env : Map[String, String] = {
    "GOOD_KEY": "value with space",
    "BAD-KEY": "skip",
  }
  let command = ccs_provider_terminal_command(env, Some("/tmp/project O'Brien"))
  assert_true(command.contains("tell application \"Terminal\""))
  assert_true(command.contains("project O"))
  assert_true(command.contains("Brien"))
  assert_true(command.contains("GOOD_KEY"))
  assert_true(command.contains("value with space"))
  assert_false(command.contains("BAD-KEY"))
}
