///|
pub async fn start(args : ArrayView[String]) -> Unit {
  let arr = args.to_array()
  if run_registered_cli_command(arr) {
    return
  }
  print_help()
}
