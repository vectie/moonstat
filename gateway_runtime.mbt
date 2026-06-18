///|
fn RuntimeService::uptime_seconds(
  _self : RuntimeService,
  started_at_ms : Int,
) -> Int {
  let elapsed = @async.now().to_int() - started_at_ms
  if elapsed < 0 {
    0
  } else {
    elapsed / 1000
  }
}
