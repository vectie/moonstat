///|
/// Lightweight wrapper around an incoming HTTP request.
///
/// `RequestReader` exposes the request body as an `@io.Reader`, the HTTP
/// method, request path, lower-case request headers and any path variables
/// captured by the router.
pub struct RequestReader {
  /// Reader for the request body stream.
  body : &@io.Reader
  /// HTTP method of the request.
  method_ : Method
  /// Full request path as received by the server.
  path : StringView
  /// Request headers. Header names are normalized to lower case by `@http`.
  headers : Map[String, String]
  /// Route parameters extracted from the matched path pattern.
  vars : Map[StringView, StringView]
}
