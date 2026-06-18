///|
fn ProxyService::register_inference_routes(
  self : ProxyService,
  router : @httpx.Router,
  auth : AuthService,
  usage : UsageService,
  config : ConfigService,
  session : SessionService,
  model : String,
  logger : @pino.Logger,
) -> Unit {
  router.add_handler(Post, "/v1/messages", (r, w) => {
    self.handle_messages(auth, usage, config, session, model, logger, r, w)
  })
  router.add_handler(Post, "/claude-desktop/v1/messages", (r, w) => {
    self.handle_messages(auth, usage, config, session, model, logger, r, w)
  })
  for method_ in @httpx.methods {
    router.add_handler(method_, "/v1beta/*path", (r, w) => {
      self.handle_gemini(usage, r, w)
    })
    router.add_handler(method_, "/gemini/v1beta/*path", (r, w) => {
      self.handle_gemini(usage, r, w)
    })
    router.add_handler(method_, "/gemini/v1/*path", (r, w) => {
      self.handle_gemini(usage, r, w)
    })
  }
  router.add_handler(Post, "/chat/completions", (r, w) => {
    self.handle_chat_completions(auth, usage, session, model, r, w)
  })
  router.add_handler(Post, "/v1/chat/completions", (r, w) => {
    self.handle_chat_completions(auth, usage, session, model, r, w)
  })
  router.add_handler(Post, "/openclaw/v1/chat/completions", (r, w) => {
    self.handle_chat_completions(
      auth,
      usage,
      session,
      model,
      r,
      w,
      app_type="openclaw",
    )
  })
  router.add_handler(Post, "/responses", (r, w) => {
    self.handle_codex_responses(auth, usage, session, model, r, w)
  })
  router.add_handler(Post, "/v1/responses", (r, w) => {
    self.handle_codex_responses(auth, usage, session, model, r, w)
  })
  router.add_handler(Post, "/responses/compact", (r, w) => {
    self.handle_codex_responses(auth, usage, session, model, r, w, compact=true)
  })
  router.add_handler(Post, "/v1/responses/compact", (r, w) => {
    self.handle_codex_responses(auth, usage, session, model, r, w, compact=true)
  })
  router.add_handler(Get, "/models", (_, w) => self.handle_models(w))
  router.add_handler(Get, "/v1/models", (_, w) => self.handle_models(w))
  router.add_handler(Get, "/claude-desktop/v1/models", (r, w) => {
    self.handle_claude_desktop_models(auth, usage, r, w)
  })
}
