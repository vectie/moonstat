///|
pub async fn start(args : ArrayView[String]) -> Unit {
  let arr = args.to_owned()
  if run_registered_cli_command(arr) {
    return
  }
  print_help()
}
