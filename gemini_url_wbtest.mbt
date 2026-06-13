///|
test "gemini url strips version root for official base" {
  let url = build_gemini_native_url(
    "https://generativelanguage.googleapis.com/v1beta", "/v1beta/models/gemini-2.5-pro:generateContent",
  )
  assert_eq(
    url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent",
  )
}

///|
test "gemini url preserves proxy prefix while stripping openai suffix" {
  let url = build_gemini_native_url(
    "https://proxy.example.com/google/v1beta/openai/chat/completions", "/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse",
  )
  assert_eq(
    url, "https://proxy.example.com/google/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse",
  )
}

///|
test "gemini full url preserves opaque relay" {
  let url = resolve_gemini_native_url(
    "https://relay.example/custom/generate-content", "/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse",
    true,
  )
  assert_eq(url, "https://relay.example/custom/generate-content?alt=sse")
}

///|
test "gemini full url preserves cloudflare vertex action" {
  let url = resolve_gemini_native_url(
    "https://gateway.ai.cloudflare.com/v1/account/gateway/google-vertex-ai/v1/projects/project/locations/us-central1/publishers/google/models/gemini-3.1-pro-preview:streamGenerateContent",
    "/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse", true,
  )
  assert_eq(
    url, "https://gateway.ai.cloudflare.com/v1/account/gateway/google-vertex-ai/v1/projects/project/locations/us-central1/publishers/google/models/gemini-3.1-pro-preview:streamGenerateContent?alt=sse",
  )
}

///|
test "gemini full url normalizes structured method path" {
  let url = resolve_gemini_native_url(
    "https://relay.example/v1/models/gemini-2.5-pro:generateContent", "/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse",
    true,
  )
  assert_eq(
    url, "https://relay.example/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse",
  )
}

///|
test "gemini url merges base and endpoint queries" {
  let url = build_gemini_native_url(
    "https://generativelanguage.googleapis.com/v1beta?key=abc", "/v1beta/models/gemini-2.5-pro:generateContent?alt=sse",
  )
  assert_eq(
    url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=abc&alt=sse",
  )
}
