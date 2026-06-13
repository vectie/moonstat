///|
test "claude desktop model list matches ccs response shape" {
  json_inspect(claude_desktop_model_list_json(), content={
    "data": [
      {
        "type": "model",
        "id": "claude-sonnet-4-6",
        "created_at": "2024-01-01T00:00:00Z",
        "supports1m": true,
      },
      {
        "type": "model",
        "id": "claude-opus-4-8",
        "created_at": "2024-01-01T00:00:00Z",
        "supports1m": true,
      },
      {
        "type": "model",
        "id": "claude-haiku-4-5",
        "created_at": "2024-01-01T00:00:00Z",
        "supports1m": true,
      },
    ],
    "has_more": false,
    "first_id": "claude-sonnet-4-6",
    "last_id": "claude-haiku-4-5",
  })
}

///|
test "codex compact responses keep compact backend endpoint" {
  assert_eq(
    codex_backend_responses_endpoint(false),
    "/backend-api/codex/responses",
  )
  assert_eq(
    codex_backend_responses_endpoint(true),
    "/backend-api/codex/responses/compact",
  )
}

///|
test "codex responses endpoints preserve request query" {
  assert_eq(
    codex_backend_responses_endpoint(
      false,
      request_path="/v1/responses?beta=true&conversation=abc",
    ),
    "/backend-api/codex/responses?beta=true&conversation=abc",
  )
  assert_eq(
    codex_backend_responses_endpoint(
      true,
      request_path="/codex/v1/responses/compact?beta=true",
    ),
    "/backend-api/codex/responses/compact?beta=true",
  )
}

///|
test "claude desktop gateway bearer token validation" {
  assert_eq(bearer_token("Bearer moon-token"), Some("moon-token"))
  assert_eq(bearer_token("bearer moon-token  "), Some("moon-token"))
  assert_eq(bearer_token("Token moon-token"), None)
  assert_true(
    claude_desktop_authorization_valid(
      { "authorization": "Bearer moon-token" },
      "moon-token",
    ),
  )
  assert_false(
    claude_desktop_authorization_valid(
      { "authorization": "Bearer wrong-token" },
      "moon-token",
    ),
  )
  assert_false(claude_desktop_authorization_valid({}, "moon-token"))
}
