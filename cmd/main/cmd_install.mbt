///|
fn cli_install_command_id(command_id : String) -> Bool {
  match command_id {
    "start"
    | "install_reroute"
    | "uninstall_reroute"
    | "install_claude_desktop"
    | "uninstall_claude_desktop"
    | "status_claude_desktop"
    | "install_codex"
    | "uninstall_codex"
    | "status_codex" => true
    _ => false
  }
}

///|
async fn run_install_cli_command(
  command_id : String,
  args : Array[String],
) -> Unit {
  match command_id {
    "start" => start_gateway(args)
    "install_reroute" => install_reroute(args)
    "uninstall_reroute" => uninstall_reroute()
    "install_claude_desktop" => install_claude_desktop(args)
    "uninstall_claude_desktop" => uninstall_claude_desktop()
    "status_claude_desktop" => status_claude_desktop()
    "install_codex" => install_codex(args)
    "uninstall_codex" => uninstall_codex()
    "status_codex" => status_codex()
    _ => ()
  }
}
