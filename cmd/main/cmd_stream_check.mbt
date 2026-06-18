///|
fn cli_stream_check_command_id(command_id : String) -> Bool {
  match command_id {
    "stream_check_provider"
    | "stream_check_all_providers"
    | "get_stream_check_config"
    | "save_stream_check_config" => true
    _ => false
  }
}

///|
async fn run_stream_check_cli_command(
  command_id : String,
  args : Array[String],
) -> Unit {
  match command_id {
    "stream_check_provider" => stream_check_provider(args)
    "stream_check_all_providers" => stream_check_all_providers(args)
    "get_stream_check_config" =>
      check_usage_endpoint(args, "/proxy/stream-check/config")
    "save_stream_check_config" => save_stream_check_config(args)
    _ => ()
  }
}
