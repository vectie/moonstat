///|
fn cli_provider_command_id(command_id : String) -> Bool {
  match command_id {
    "get_providers"
    | "get_current_provider"
    | "add_provider"
    | "update_provider"
    | "delete_provider"
    | "remove_provider_from_live_config"
    | "switch_provider"
    | "sync_current_providers_live"
    | "read_live_provider_settings"
    | "open_provider_terminal"
    | "import_default_config"
    | "get_claude_desktop_status"
    | "get_claude_desktop_default_routes"
    | "import_claude_desktop_providers_from_claude"
    | "ensure_claude_desktop_official_provider"
    | "provider_live_ids"
    | "provider_live_get"
    | "provider_import_live"
    | "get_opencode_live_provider_ids"
    | "get_openclaw_live_provider_ids"
    | "get_openclaw_live_provider"
    | "get_hermes_live_provider_ids"
    | "get_hermes_live_provider"
    | "import_opencode_providers_from_live"
    | "import_openclaw_providers_from_live"
    | "import_hermes_providers_from_live"
    | "get_universal_providers"
    | "get_universal_provider"
    | "upsert_universal_provider"
    | "delete_universal_provider"
    | "sync_universal_provider"
    | "get_provider_presets"
    | "test_api_endpoints"
    | "update_providers_sort_order"
    | "get_custom_endpoints"
    | "add_custom_endpoint"
    | "remove_custom_endpoint"
    | "update_endpoint_last_used"
    | "fetch_models"
    | "model_candidates" => true
    _ => false
  }
}

///|
async fn run_provider_cli_command(
  command_id : String,
  args : Array[String],
) -> Unit {
  match command_id {
    "get_providers" => check_providers(args)
    "get_current_provider" => check_current_provider(args)
    "add_provider" => add_provider(args)
    "update_provider" => update_provider(args)
    "delete_provider" => delete_provider(args)
    "remove_provider_from_live_config" => remove_provider_from_live_config(args)
    "switch_provider" => switch_provider(args)
    "sync_current_providers_live" => sync_current_providers_live(args)
    "read_live_provider_settings" => check_live_provider_settings(args)
    "open_provider_terminal" => open_provider_terminal(args)
    "import_default_config" => import_default_config(args)
    "get_claude_desktop_status" =>
      check_usage_endpoint(args, "/providers/claude-desktop/status")
    "get_claude_desktop_default_routes" =>
      check_usage_endpoint(args, "/providers/claude-desktop/default-routes")
    "import_claude_desktop_providers_from_claude" =>
      check_json_post_endpoint(
        args, "/providers/claude-desktop/import", "Provider",
      )
    "ensure_claude_desktop_official_provider" =>
      check_json_post_endpoint(
        args, "/providers/claude-desktop/official", "Provider",
      )
    "provider_live_ids" => check_provider_live_ids(args)
    "provider_live_get" => check_provider_live_provider(args)
    "provider_import_live" => import_provider_live(args)
    "get_opencode_live_provider_ids" =>
      check_named_live_provider_ids(args, "opencode")
    "get_openclaw_live_provider_ids" =>
      check_named_live_provider_ids(args, "openclaw")
    "get_openclaw_live_provider" => check_named_live_provider(args, "openclaw")
    "get_hermes_live_provider_ids" =>
      check_named_live_provider_ids(args, "hermes")
    "get_hermes_live_provider" => check_named_live_provider(args, "hermes")
    "import_opencode_providers_from_live" =>
      import_named_live_providers(args, "opencode")
    "import_openclaw_providers_from_live" =>
      import_named_live_providers(args, "openclaw")
    "import_hermes_providers_from_live" =>
      import_named_live_providers(args, "hermes")
    "get_universal_providers" => check_universal_providers(args)
    "get_universal_provider" => check_universal_provider(args)
    "upsert_universal_provider" => upsert_universal_provider(args)
    "delete_universal_provider" => delete_universal_provider(args)
    "sync_universal_provider" => sync_universal_provider(args)
    "get_provider_presets" => check_provider_presets(args)
    "test_api_endpoints" => test_api_endpoints(args)
    "update_providers_sort_order" => update_providers_sort_order(args)
    "get_custom_endpoints" => check_provider_custom_endpoints(args)
    "add_custom_endpoint" => add_provider_custom_endpoint(args)
    "remove_custom_endpoint" => remove_provider_custom_endpoint(args)
    "update_endpoint_last_used" => update_provider_endpoint_last_used(args)
    "fetch_models" => fetch_provider_models(args)
    "model_candidates" => print_model_candidates(args)
    _ => ()
  }
}
