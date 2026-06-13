///|
pub struct TrafficStats {
  mut total_requests : Int
  mut message_requests : Int
  mut streaming_requests : Int
  mut non_streaming_requests : Int
  mut successful_responses : Int
  mut failed_responses : Int
  mut unauthorized_responses : Int
  mut bad_requests : Int
  mut upstream_errors : Int
  mut input_tokens : Int
  mut output_tokens : Int
  mut request_bytes : Int
  mut response_bytes : Int
}

///|
pub fn TrafficStats::new() -> TrafficStats {
  {
    total_requests: 0,
    message_requests: 0,
    streaming_requests: 0,
    non_streaming_requests: 0,
    successful_responses: 0,
    failed_responses: 0,
    unauthorized_responses: 0,
    bad_requests: 0,
    upstream_errors: 0,
    input_tokens: 0,
    output_tokens: 0,
    request_bytes: 0,
    response_bytes: 0,
  }
}

///|
pub fn TrafficStats::record_inbound(
  self : TrafficStats,
  request_bytes : Int,
) -> Unit {
  self.total_requests += 1
  self.message_requests += 1
  self.request_bytes += request_bytes
}

///|
pub fn TrafficStats::record_stream_mode(
  self : TrafficStats,
  stream : Bool,
) -> Unit {
  if stream {
    self.streaming_requests += 1
  } else {
    self.non_streaming_requests += 1
  }
}

///|
pub fn TrafficStats::record_bad_request(self : TrafficStats) -> Unit {
  self.bad_requests += 1
  self.failed_responses += 1
}

///|
pub fn TrafficStats::record_unauthorized(self : TrafficStats) -> Unit {
  self.unauthorized_responses += 1
  self.failed_responses += 1
}

///|
pub fn TrafficStats::record_upstream_error(
  self : TrafficStats,
  response_bytes : Int,
) -> Unit {
  self.upstream_errors += 1
  self.failed_responses += 1
  self.response_bytes += response_bytes
}

///|
pub fn TrafficStats::record_internal_error(self : TrafficStats) -> Unit {
  self.failed_responses += 1
}

///|
pub fn TrafficStats::record_success(
  self : TrafficStats,
  input_tokens : Int,
  output_tokens : Int,
  response_bytes : Int,
) -> Unit {
  self.successful_responses += 1
  self.input_tokens += input_tokens
  self.output_tokens += output_tokens
  self.response_bytes += response_bytes
}

///|
pub fn TrafficStats::to_json(self : TrafficStats) -> Json {
  {
    "total_requests": Json::number(self.total_requests.to_double()),
    "message_requests": Json::number(self.message_requests.to_double()),
    "streaming_requests": Json::number(self.streaming_requests.to_double()),
    "non_streaming_requests": Json::number(
      self.non_streaming_requests.to_double(),
    ),
    "successful_responses": Json::number(self.successful_responses.to_double()),
    "failed_responses": Json::number(self.failed_responses.to_double()),
    "unauthorized_responses": Json::number(
      self.unauthorized_responses.to_double(),
    ),
    "bad_requests": Json::number(self.bad_requests.to_double()),
    "upstream_errors": Json::number(self.upstream_errors.to_double()),
    "input_tokens": Json::number(self.input_tokens.to_double()),
    "output_tokens": Json::number(self.output_tokens.to_double()),
    "request_bytes": Json::number(self.request_bytes.to_double()),
    "response_bytes": Json::number(self.response_bytes.to_double()),
  }.to_json()
}
