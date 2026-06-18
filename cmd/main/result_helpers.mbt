///|
async fn[T] cli_async_result(f : async () -> T raise Error) -> Result[T, Error] {
  try f() catch {
    error => Err(error)
  } noraise {
    value => Ok(value)
  }
}
