import Foundation

/// Stubs `URLSession` responses in unit tests. Register handlers before each test.
final class MockURLProtocol: URLProtocol {

  nonisolated(unsafe) static var handlers:
    [(canHandle: (URLRequest) -> Bool, respond: (URLRequest) throws -> (HTTPURLResponse, Data))] = []

  static func reset() {
    handlers = []
  }

  static func register(
    matching: @escaping (URLRequest) -> Bool,
    response: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
  ) {
    handlers.append((matching, response))
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let client else { return }
    do {
      for handler in Self.handlers where handler.canHandle(request) {
        let (http, data) = try handler.respond(request)
        client.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: data)
        client.urlProtocolDidFinishLoading(self)
        return
      }
      let response = HTTPURLResponse(
        url: request.url ?? URL(string: "https://example.com")!,
        statusCode: 404,
        httpVersion: nil,
        headerFields: nil
      )!
      client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client.urlProtocol(self, didLoad: Data())
      client.urlProtocolDidFinishLoading(self)
    } catch {
      client.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

extension URLSession {
  /// Ephemeral session that routes all requests through `MockURLProtocol`.
  static var mockEphemeral: URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }
}
