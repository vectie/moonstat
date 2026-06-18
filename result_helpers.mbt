///|
fn[T] moon_result(f : () -> T raise Error) -> Result[T, Error] {
  try f() catch {
    error => Err(error)
  } noraise {
    value => Ok(value)
  }
}

///|
async fn[T] moon_async_result(
  f : async () -> T raise Error,
) -> Result[T, Error] {
  try f() catch {
    error => Err(error)
  } noraise {
    value => Ok(value)
  }
}
