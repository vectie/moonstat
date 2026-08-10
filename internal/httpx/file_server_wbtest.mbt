///|
test "static file server sends SVG with an image MIME type" {
  assert_eq(static_content_type("assets/moongate.svg"), "image/svg+xml")
  assert_eq(
    static_content_type("assets/moongate.bin"),
    "application/octet-stream",
  )
}

///|
test "static file server ignores cache-busting query strings" {
  assert_eq(
    static_request_path("/assets/moongate.js?v=12"),
    Some("/assets/moongate.js"),
  )
}

///|
test "static file server rejects adversarial traversal mutations" {
  let traversal_segments = [".", "..", "%2e", "%2E%2E", "%252e%252e", "..\\.."]
  let tails = ["", "/moon.mod", "/providers.json", "/assets.js"]
  for segment in traversal_segments {
    for tail in tails {
      assert_eq(static_request_path("/assets/\{segment}\{tail}"), None)
    }
  }
  assert_eq(static_request_path("/assets/safe/../secret"), None)
  assert_eq(static_request_path("/assets/safe.js#fragment"), None)
  assert_eq(static_request_path("assets/no-leading-slash.js"), None)
}
