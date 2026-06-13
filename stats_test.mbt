///|
test "traffic stats records proxy counters" {
  let stats = TrafficStats::new()
  stats.record_inbound(120)
  stats.record_stream_mode(false)
  stats.record_unauthorized()
  stats.record_inbound(80)
  stats.record_stream_mode(true)
  stats.record_success(11, 17, 240)
  let json = stats.to_json()
  json_inspect(json, content={
    "total_requests": 2,
    "message_requests": 2,
    "streaming_requests": 1,
    "non_streaming_requests": 1,
    "successful_responses": 1,
    "failed_responses": 1,
    "unauthorized_responses": 1,
    "bad_requests": 0,
    "upstream_errors": 0,
    "input_tokens": 11,
    "output_tokens": 17,
    "request_bytes": 200,
    "response_bytes": 240,
  })
}
