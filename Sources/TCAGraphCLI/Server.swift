import Foundation
import Network

enum ServerError: Error, CustomStringConvertible {
  case invalidPort(UInt16)

  var description: String {
    switch self {
    case .invalidPort(let p): return "Invalid port: \(p)"
    }
  }
}

struct HTTPRequest {
  let method: String
  let path: String
  let headers: [String: String]
  let body: Data
}

struct HTTPResponse {
  let status: Int
  let statusText: String
  let headers: [String: String]
  let body: Data

  static func json(_ status: Int, _ statusText: String, _ obj: [String: Any]) -> HTTPResponse {
    let body = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])) ?? Data()
    return HTTPResponse(
      status: status,
      statusText: statusText,
      headers: ["Content-Type": "application/json"],
      body: body
    )
  }

  func serialize() -> Data {
    var allHeaders = headers
    allHeaders["Content-Length"] = String(body.count)
    allHeaders["Cache-Control"] = "no-store"

    var head = "HTTP/1.1 \(status) \(statusText)\r\n"
    for (k, v) in allHeaders {
      head += "\(k): \(v)\r\n"
    }
    head += "\r\n"
    var out = Data(head.utf8)
    out.append(body)
    return out
  }
}

final class LocalHelper {
  private let listener: NWListener
  private let queue = DispatchQueue(label: "tca-graph.server", qos: .userInitiated)
  private let staticRoot: URL?
  private let graphJSON: Data?
  let port: UInt16

  init(port: UInt16, staticRoot: URL? = nil, graphJSON: Data? = nil) throws {
    guard let p = NWEndpoint.Port(rawValue: port) else {
      throw ServerError.invalidPort(port)
    }
    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true
    params.acceptLocalOnly = true
    self.port = port
    self.staticRoot = staticRoot
    self.graphJSON = graphJSON
    self.listener = try NWListener(using: params, on: p)
  }

  func start() throws {
    let semaphore = DispatchSemaphore(value: 0)
    var startupError: Error?

    listener.stateUpdateHandler = { state in
      switch state {
      case .ready:
        semaphore.signal()
      case .failed(let err):
        startupError = err
        semaphore.signal()
      default: break
      }
    }
    listener.newConnectionHandler = { [weak self] conn in
      self?.handle(conn)
    }
    listener.start(queue: queue)

    semaphore.wait()
    if let err = startupError { throw err }
  }

  // MARK: - Connection handling

  private func handle(_ conn: NWConnection) {
    conn.stateUpdateHandler = { state in
      switch state {
      case .failed, .cancelled: conn.cancel()
      default: break
      }
    }
    conn.start(queue: queue)
    receive(on: conn, buffer: Data())
  }

  private func receive(on conn: NWConnection, buffer: Data) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, _ in
      guard let self else { return }
      var buf = buffer
      if let data { buf.append(data) }

      if let req = parseRequest(buf) {
        let resp = self.route(req)
        conn.send(content: resp.serialize(), completion: .contentProcessed { _ in conn.cancel() })
        return
      }

      if isComplete {
        conn.cancel()
        return
      }
      self.receive(on: conn, buffer: buf)
    }
  }

  // MARK: - Routing

  private func route(_ req: HTTPRequest) -> HTTPResponse {
    switch (req.method, req.path) {
    case ("GET", "/health"):
      return .json(200, "OK", ["status": "ok", "version": "0.1.0"])
    case ("GET", "/graph.json"):
      // Explicit 404 when no graph is loaded, otherwise the static-file fallback below
      // would SPA-serve index.html and the viewer would try to parse HTML as JSON.
      if let data = graphJSON {
        return HTTPResponse(
          status: 200, statusText: "OK",
          headers: ["Content-Type": "application/json"],
          body: data
        )
      }
      return .json(404, "Not Found", ["error": "no graph loaded — run `tca-graph serve <path>`"])
    case ("GET", _):
      if staticRoot != nil { return serveStatic(path: req.path) }
      return .json(404, "Not Found", ["error": "no static root"])
    default:
      return .json(404, "Not Found", ["error": "no route \(req.method) \(req.path)"])
    }
  }

  private func serveStatic(path: String) -> HTTPResponse {
    guard let root = staticRoot else {
      return .json(404, "Not Found", ["error": "no static root"])
    }
    let trimmed = String(path.drop(while: { $0 == "/" }))
    let relative = trimmed.isEmpty ? "index.html" : trimmed

    // Reject path traversal — candidate must resolve *inside* root.
    // A raw hasPrefix check would admit sibling directories that merely share the prefix
    // (e.g. root "/a/b/dist" would match "/a/b/dist-backup"), so we compare with a
    // trailing separator or require an exact match on root itself.
    let candidate = root.appendingPathComponent(relative).standardizedFileURL
    let rootPath = root.standardizedFileURL.path
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard candidate.path == rootPath || candidate.path.hasPrefix(rootPrefix) else {
      return .json(403, "Forbidden", ["error": "path traversal"])
    }
    if FileManager.default.fileExists(atPath: candidate.path),
       let data = try? Data(contentsOf: candidate) {
      return HTTPResponse(
        status: 200, statusText: "OK",
        headers: ["Content-Type": mimeType(for: candidate.pathExtension)],
        body: data
      )
    }
    // SPA fallback: unknown GETs serve index.html so client-side routes work.
    let indexURL = root.appendingPathComponent("index.html")
    if let indexData = try? Data(contentsOf: indexURL) {
      return HTTPResponse(
        status: 200, statusText: "OK",
        headers: ["Content-Type": "text/html; charset=utf-8"],
        body: indexData
      )
    }
    return .json(404, "Not Found", ["error": "not found: \(relative)"])
  }
}

private func mimeType(for ext: String) -> String {
  switch ext.lowercased() {
  case "html", "htm": return "text/html; charset=utf-8"
  case "js", "mjs":   return "application/javascript; charset=utf-8"
  case "css":         return "text/css; charset=utf-8"
  case "json":        return "application/json; charset=utf-8"
  case "svg":         return "image/svg+xml"
  case "png":         return "image/png"
  case "jpg", "jpeg": return "image/jpeg"
  case "webp":        return "image/webp"
  case "woff":        return "font/woff"
  case "woff2":       return "font/woff2"
  case "ico":         return "image/x-icon"
  case "map":         return "application/json; charset=utf-8"
  default:            return "application/octet-stream"
  }
}

// MARK: - HTTP parsing

private func parseRequest(_ data: Data) -> HTTPRequest? {
  let sep = Data("\r\n\r\n".utf8)
  guard let headerRange = data.range(of: sep) else { return nil }

  let headerData = data.subdata(in: 0..<headerRange.lowerBound)
  guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
  let lines = headerString.components(separatedBy: "\r\n")
  guard let firstLine = lines.first else { return nil }
  let parts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
  guard parts.count >= 2 else { return nil }

  var headers: [String: String] = [:]
  for line in lines.dropFirst() {
    guard let colon = line.firstIndex(of: ":") else { continue }
    let name = String(line[..<colon]).lowercased()
    let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    headers[name] = value
  }

  let contentLength = Int(headers["content-length"] ?? "0") ?? 0
  let bodyStart = headerRange.upperBound
  let available = data.count - bodyStart
  if available < contentLength { return nil }
  let body = contentLength > 0 ? data.subdata(in: bodyStart..<(bodyStart + contentLength)) : Data()

  return HTTPRequest(method: parts[0], path: parts[1], headers: headers, body: body)
}
