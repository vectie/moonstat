///|
test "fuzz canonical json is idempotent and insertion-order independent" {
  let fuzz = AdversarialFuzzer::new(0x4a534f4eL)
  for iteration in 0..<2_000 {
    let value = fuzz.json(4)
    let permuted = adversarial_permute_json(value)
    let canonical = canonical_json_string(value)
    let reparsed = @json.parse(canonical) catch {
      err =>
        fail(
          "seed=0x4a534f4e iteration=\{iteration} emitted invalid JSON: \{err}",
        )
    }
    assert_eq(canonical_json_string(reparsed), canonical)
    assert_eq(canonical_json_string(permuted), canonical)
    assert_eq(short_value_hash(Some(permuted)), short_value_hash(Some(value)))
  }
}

///|
test "fuzz usage parsers are total and never return negative tokens" {
  let fuzz = AdversarialFuzzer::new(0x55534147L)
  for iteration in 0..<3_000 {
    let value = fuzz.json(5)
    let events = [value, adversarial_permute_json(value), fuzz.json(3)]
    let parsed = [
      token_usage_from_claude_response(value),
      token_usage_from_codex_response(value),
      token_usage_from_openai_response(value),
      token_usage_from_codex_response_auto(value),
      token_usage_from_gemini_response(value),
      token_usage_from_claude_stream_events(events),
      token_usage_from_codex_stream_events_auto(events),
      token_usage_from_openai_stream_events(events),
      token_usage_from_gemini_stream_chunks(events),
    ]
    for usage in parsed {
      match usage {
        Some(usage) if usage.input_tokens < 0 ||
          usage.output_tokens < 0 ||
          usage.cache_read_tokens < 0 ||
          usage.cache_creation_tokens < 0 =>
          fail("seed=0x55534147 iteration=\{iteration} returned negative usage")
        _ => ()
      }
    }
  }
}

///|
test "fuzz provider import validation is total and non-mutating" {
  let proxy = ProxyService::new("127.0.0.1", 15721)
  let baseline = proxy.moon_export_providers_json().stringify()
  let fuzz = AdversarialFuzzer::new(0x494d5054L)
  for iteration in 0..<2_000 {
    let candidate = fuzz.json(5)
    ignore(proxy.moon_apply_import_providers(candidate, validate_only=true))
    let current = proxy.moon_export_providers_json().stringify()
    if current != baseline {
      fail("seed=0x494d5054 iteration=\{iteration} mutated validation state")
    }
  }
}

///|
test "fuzz invalid provider imports are atomic" {
  let proxy = ProxyService::new("127.0.0.1", 15721)
  let baseline = proxy.moon_export_providers_json().stringify()
  let fuzz = AdversarialFuzzer::new(0x41544f4dL)
  let invalid_values = [
    Json::null(),
    Json::boolean(false),
    Json::number(1.0),
    Json::string("bad"),
    Json::array([]),
  ]
  for iteration in 0..<1_000 {
    let app = moon_suite_app_types()[fuzz.next(moon_suite_app_types().length())]
    let provider_id = fuzz.ascii(1, 64)
    let invalid = invalid_values[fuzz.next(invalid_values.length())]
    let providers : Map[String, Json] = Map([])
    providers[provider_id] = invalid
    let root : Map[String, Json] = Map([])
    root[app] = Json::object(providers)
    assert_true(proxy.moon_apply_import_providers(Json::object(root)) is Err(_))
    if proxy.moon_export_providers_json().stringify() != baseline {
      fail("seed=0x41544f4d iteration=\{iteration} partially applied import")
    }
  }
}
