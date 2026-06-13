///|
async test "codex config install writes ccs-style local provider block" {
  @fsx.with_temporary_directory("moonstat-codex-config-XXXXXX", tmpdir => {
    let result = install_proxy_config_at(tmpdir, "0.0.0.0", 15721, "gpt-5")
    guard result is Ok(installed) else {
      fail("expected codex config install to succeed")
    }
    assert_eq(installed.base_url, "http://127.0.0.1:15721/v1")
    assert_eq(installed.model, "gpt-5")
    let content = @fsx.read_file(installed.config_path)
    inspect(
      content,
      content=(
        #|# >>> moonstat managed codex proxy
        #|model = "gpt-5"
        #|model_provider = "moonstat"
        #|
        #|[model_providers.moonstat]
        #|name = "Moonstat"
        #|base_url = "http://127.0.0.1:15721/v1"
        #|wire_api = "responses"
        #|experimental_bearer_token = "moonstat-local-proxy"
        #|# <<< moonstat managed codex proxy
        #|
      ),
    )
  })
}

///|
async test "codex config reinstall replaces only managed block" {
  @fsx.with_temporary_directory("moonstat-codex-reinstall-XXXXXX", tmpdir => {
    let config_dir = @pathx.join(tmpdir, ".codex")
    @fsx.make_directory(config_dir, recursive=true, exists_ok=true)
    let path = @pathx.join(config_dir, "config.toml")
    @fsx.write_to_file(
      path,
      (
        #|approval_policy = "on-request"
        #|
        #|# >>> moonstat managed codex proxy
        #|model = "old"
        #|model_provider = "moonstat"
        #|# <<< moonstat managed codex proxy
        #|
        #|[mcp_servers.fetch]
        #|command = "uvx"
        #|
      ),
    )

    let result = install_proxy_config_at(tmpdir, "127.0.0.1", 17890, "")
    guard result is Ok(installed) else {
      fail("expected codex config reinstall to succeed")
    }
    assert_eq(installed.config_path, path)
    let content = @fsx.read_file(path)
    assert_eq(
      content,
      (
        #|approval_policy = "on-request"
        #|
        #|[mcp_servers.fetch]
        #|command = "uvx"
        #|
        #|# >>> moonstat managed codex proxy
        #|model = "gpt-5"
        #|model_provider = "moonstat"
        #|
        #|[model_providers.moonstat]
        #|name = "Moonstat"
        #|base_url = "http://127.0.0.1:17890/v1"
        #|wire_api = "responses"
        #|experimental_bearer_token = "moonstat-local-proxy"
        #|# <<< moonstat managed codex proxy
        #|
      ),
    )
  })
}

///|
async test "codex config uninstall preserves user config" {
  @fsx.with_temporary_directory("moonstat-codex-uninstall-XXXXXX", tmpdir => {
    let result = install_proxy_config_at(tmpdir, "127.0.0.1", 15721, "gpt-5")
    guard result is Ok(installed) else {
      fail("expected codex config install to succeed")
    }
    let existing = @fsx.read_file(installed.config_path)
    @fsx.write_to_file(
      installed.config_path,
      "approval_policy = \"on-request\"\n\n\{existing}[mcp_servers.fetch]\ncommand = \"uvx\"\n",
    )
    let uninstall_result = uninstall_proxy_config_at(tmpdir)
    guard uninstall_result is Ok(_) else {
      fail("expected codex config uninstall to succeed")
    }
    let content = @fsx.read_file(installed.config_path)
    assert_eq(
      content,
      (
        #|approval_policy = "on-request"
        #|
        #|[mcp_servers.fetch]
        #|command = "uvx"
        #|
      ),
    )
  })
}

///|
async test "codex config status reports managed values" {
  @fsx.with_temporary_directory("moonstat-codex-status-XXXXXX", tmpdir => {
    ignore(install_proxy_config_at(tmpdir, "127.0.0.1", 15721, "gpt-5"))
    let status = status_at(tmpdir)
    assert_true(status.configured)
    assert_true(status.base_url is Some("http://127.0.0.1:15721/v1"))
    assert_true(status.model is Some("gpt-5"))
  })
}
