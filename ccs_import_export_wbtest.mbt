///|
test "ccs backup filenames are filesystem safe" {
  assert_eq(ccs_backup_filename("nested/name:one"), "nested-name-one.db")
  assert_eq(ccs_backup_filename("ready.db"), "ready.db")
  assert_eq(ccs_backup_filename("snapshot.json"), "snapshot.json")
}

///|
test "ccs import proxy ints accept camel and snake case keys" {
  guard Json::object({ "listenPort": Json::number(123.0) }) is Object(camel) else {
    fail("expected object")
  }
  guard Json::object({ "listen_port": Json::number(456.0) }) is Object(snake) else {
    fail("expected object")
  }
  assert_eq(ccs_json_int_from_map_any(camel, ["listenPort"]), Some(123))
  assert_eq(
    ccs_json_int_from_map_any(snake, ["listenPort", "listen_port"]),
    Some(456),
  )
  assert_eq(ccs_json_int_from_map_any(camel, ["missing"]), None)
}
