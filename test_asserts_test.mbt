///|
fn[T : Eq] assert_eq(actual : T, expected : T) -> Unit raise {
  assert_true(actual == expected)
}
