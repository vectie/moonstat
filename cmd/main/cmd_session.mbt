///|
fn cli_session_command_id(command_id : String) -> Bool {
  match command_id {
    "list_sessions"
    | "get_session_messages"
    | "launch_session_terminal"
    | "delete_session"
    | "delete_sessions"
    | "read_omo_local_file"
    | "get_current_omo_provider_id"
    | "disable_current_omo"
    | "read_omo_slim_local_file"
    | "get_current_omo_slim_provider_id"
    | "disable_current_omo_slim" => true
    _ => false
  }
}

///|
async fn run_session_cli_command(
  command_id : String,
  args : Array[String],
) -> Unit {
  match command_id {
    "list_sessions" => check_usage_endpoint(args, "/sessions")
    "get_session_messages" =>
      check_usage_endpoint(args, session_messages_path(args))
    "launch_session_terminal" =>
      check_json_post_endpoint(
        args,
        launch_session_terminal_path(args),
        "Session",
      )
    "delete_session" =>
      check_json_post_endpoint(args, delete_session_path(args), "Session")
    "delete_sessions" => delete_sessions(args)
    "read_omo_local_file" => check_usage_endpoint(args, "/providers/omo/file")
    "get_current_omo_provider_id" =>
      check_usage_endpoint(args, "/providers/omo/current")
    "disable_current_omo" =>
      check_json_post_endpoint(args, "/providers/omo/disable", "OMO")
    "read_omo_slim_local_file" =>
      check_usage_endpoint(args, "/providers/omo-slim/file")
    "get_current_omo_slim_provider_id" =>
      check_usage_endpoint(args, "/providers/omo-slim/current")
    "disable_current_omo_slim" =>
      check_json_post_endpoint(args, "/providers/omo-slim/disable", "OMO")
    _ => ()
  }
}
