///|
test "fuzz generated model URLs split without authority confusion" {
  let fuzz = AdversarialFuzzer::new(0x4d4f444cL)
  for iteration in 0..<5_000 {
    let scheme = if fuzz.next(2) == 0 { "http" } else { "https" }
    let host = "node-\{fuzz.next(1_000_000)}.example.com"
    let port = if fuzz.next(3) == 0 { ":\{1 + fuzz.next(65_535)}" } else { "" }
    let path = "/v\{1 + fuzz.next(9)}/models/\{fuzz.ascii(1, 32)}?page=\{fuzz.next(10_000)}"
    let url = "\{scheme}://\{host}\{port}\{path}"
    match models_url_target(url) {
      Ok(target) => {
        assert_eq(target.origin, "\{scheme}://\{host}\{port}")
        assert_eq(target.path, path)
      }
      Err(err) =>
        fail("seed=0x4d4f444c iteration=\{iteration} rejected=\{url}: \{err}")
    }
  }
}

///|
test "fuzz generated authenticated proxy URLs validate" {
  let fuzz = AdversarialFuzzer::new(0x50525859L)
  let schemes = ["http", "https", "socks5", "socks5h"]
  for iteration in 0..<5_000 {
    let scheme = schemes[fuzz.next(schemes.length())]
    let credentials = if fuzz.next(2) == 0 {
      "user-\{fuzz.next(10_000)}:pass%2F\{fuzz.next(10_000)}@"
    } else {
      ""
    }
    let host = if fuzz.next(4) == 0 {
      "[2001:db8::\{1 + fuzz.next(9)}]"
    } else {
      "proxy-\{fuzz.next(100_000)}.example.com"
    }
    let port = 1 + fuzz.next(65_535)
    let url = "\{scheme}://\{credentials}\{host}:\{port}"
    if !upstream_proxy_url_is_valid(url) {
      fail("seed=0x50525859 iteration=\{iteration} rejected=\{url}")
    }
  }
}

///|
test "fuzz outbound URLs reject adversarial grammar" {
  let fuzz = AdversarialFuzzer::new(0x55524c58L)
  let invalid = [
    "", "api.example.com/v1/models", "ftp://api.example.com/v1/models", "https://",
    "https:///v1/models", "https://user@api.example.com/v1/models", "https://api.example.com:0/v1/models",
    "https://api.example.com:65536/v1/models", "https://api.example.com:notaport/v1/models",
    "https://api..example.com/v1/models", "https://-api.example.com/v1/models", "https://api.example.com/v1/models#fragment",
    "https://api.example.com\\v1\\models", "https://api.example.com\r\nx-header:evil",
    " javascript://api.example.com", "https://[:::1]/v1/models", "https://[1:2:3]/v1/models",
    "https://[1:2:3:4:5:6:7:8:9]/v1/models", "https://[gggg::1]/v1/models",
  ]
  let invalid_proxies = [
    "http://", "socks5://", "ftp://proxy.example.com:21", "http://proxy.example.com:0",
    "http://proxy.example.com:65536", "http://proxy.example.com:notaport", "http://@proxy.example.com:80",
    "http://a@b@proxy.example.com:80", "http://proxy.example.com:80/path", "http://proxy.example.com:80?query=1",
    "http://proxy.example.com:80#fragment", "http://proxy..example.com:80", "http://proxy.example.com:80\r\nx:evil",
    "http://user%:pass@proxy.example.com:80", "http://user%0:pass@proxy.example.com:80",
    "http://user%gg:pass@proxy.example.com:80", "http://user[admin]:pass@proxy.example.com:80",
  ]
  for iteration in 0..<5_000 {
    let model_url = invalid[fuzz.next(invalid.length())]
    if models_url_target(model_url) is Ok(_) {
      fail("seed=0x55524c58 iteration=\{iteration} model=\{model_url}")
    }
    let proxy_url = invalid_proxies[fuzz.next(invalid_proxies.length())]
    if upstream_proxy_url_is_valid(proxy_url) {
      fail("seed=0x55524c58 iteration=\{iteration} proxy=\{proxy_url}")
    }
  }
}

///|
test "adversarial outbound URLs reject oversized input" {
  let oversized = "a".repeat(16_385)
  assert_true(models_url_target("https://\{oversized}") is Err(_))
  assert_false(upstream_proxy_url_is_valid("http://\{oversized}"))
}
