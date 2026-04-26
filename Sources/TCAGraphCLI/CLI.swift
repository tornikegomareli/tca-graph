import Foundation
import TCAGraphModel
import TCAGraphParser

@main
struct CLI {
  static func main() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
      printUsage()
      exit(1)
    }

    switch args[1] {
    case "analyze":
      runAnalyze(positional: Array(args.dropFirst(2)))
    case "serve":
      runServe(positional: Array(args.dropFirst(2)))
    default:
      printUsage()
      exit(1)
    }
  }

  static func runAnalyze(positional: [String]) {
    var rootPath = "."
    var outputPath: String?

    var i = 0
    while i < positional.count {
      let a = positional[i]
      if a == "-o" || a == "--output" {
        if i + 1 < positional.count {
          outputPath = positional[i + 1]
          i += 2
          continue
        } else {
          FileHandle.standardError.write(Data("Missing value for \(a)\n".utf8))
          exit(1)
        }
      }
      if !a.hasPrefix("-") {
        rootPath = a
      }
      i += 1
    }

    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL

    FileHandle.standardError.write(Data("Analyzing \(rootURL.path)\n".utf8))

    guard let data = buildGraphJSON(rootURL: rootURL) else {
      FileHandle.standardError.write(Data("Failed to produce graph JSON.\n".utf8))
      exit(2)
    }

    if let outputPath {
      do {
        try data.write(to: URL(fileURLWithPath: outputPath))
        FileHandle.standardError.write(Data("Wrote \(outputPath)\n".utf8))
      } catch {
        FileHandle.standardError.write(Data("Write failed: \(error)\n".utf8))
        exit(4)
      }
    } else {
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }
  }

  static func runServe(positional: [String]) {
    var port: UInt16 = 8765
    var rootPath: String?
    var autoOpen = true
    var staticRootOverride: String?

    var i = 0
    while i < positional.count {
      let a = positional[i]
      if a == "-p" || a == "--port" {
        guard i + 1 < positional.count, let p = UInt16(positional[i + 1]) else {
          FileHandle.standardError.write(Data("Missing or invalid value for \(a)\n".utf8))
          exit(1)
        }
        port = p
        i += 2
        continue
      }
      if a == "--no-open" { autoOpen = false; i += 1; continue }
      if a == "--viewer" {
        guard i + 1 < positional.count else {
          FileHandle.standardError.write(Data("Missing value for --viewer\n".utf8))
          exit(1)
        }
        staticRootOverride = positional[i + 1]
        i += 2
        continue
      }
      if !a.hasPrefix("-") && rootPath == nil { rootPath = a }
      i += 1
    }

    let staticRoot = findViewerDist(override: staticRootOverride)
    if staticRoot == nil {
      FileHandle.standardError.write(Data("""
      Warning: viewer dist/ not found — the web UI won't be served.
      Looked in: $PWD/viewer/dist, alongside the binary.
      Pass --viewer <path/to/dist> to override.

      """.utf8))
    }

    // Produce the graph JSON in memory so the viewer fetches the fresh analysis.
    let graphJSON: Data?
    if let rootPath {
      let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
      FileHandle.standardError.write(Data("Analyzing \(rootURL.path)\n".utf8))
      graphJSON = buildGraphJSON(rootURL: rootURL)
    } else {
      graphJSON = nil
      FileHandle.standardError.write(
        Data("No path provided — serving without a graph. Pass a path like: tca-graph serve <path>\n".utf8)
      )
    }

    let helper: LocalHelper
    do {
      helper = try LocalHelper(port: port, staticRoot: staticRoot, graphJSON: graphJSON)
      try helper.start()
    } catch {
      FileHandle.standardError.write(Data("Helper failed to start on port \(port): \(error)\n".utf8))
      exit(5)
    }

    let url = "http://127.0.0.1:\(helper.port)"
    let banner = """
    tca-graph serving on \(url)
      GET /            viewer
      GET /graph.json  analyzed graph
    Press Ctrl+C to stop.

    """
    FileHandle.standardError.write(Data(banner.utf8))

    if autoOpen && staticRoot != nil {
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      proc.arguments = [url]
      try? proc.run()
    }

    dispatchMain()
  }

  static func buildGraphJSON(rootURL: URL) -> Data? {
    let discovery: DiscoveryResult
    do {
      discovery = try PackageDiscovery.discover(root: rootURL)
    } catch {
      FileHandle.standardError.write(Data("Discovery failed: \(error)\n".utf8))
      return nil
    }

    FileHandle.standardError.write(
      Data("Found \(discovery.modules.count) modules, \(discovery.allSwiftFiles.count) Swift files\n".utf8)
    )

    let result = DeclarationIndexer.index(
      files: discovery.allSwiftFiles,
      fileToModule: discovery.fileToModule
    )

    FileHandle.standardError.write(
      Data("Indexed \(result.nodes.count) reducers, \(result.edges.count) edges, \(result.sharedStorages.count) shared storages, \(result.diagnostics.count) diagnostics\n".utf8)
    )

    let iso = ISO8601DateFormatter()
    let graph = Graph(
      generator: GeneratorInfo(name: "tca-graph", version: "0.3.0"),
      generatedAt: iso.string(from: Date()),
      source: Source(
        rootPath: rootURL.path,
        gitCommit: currentGitCommit(at: rootURL),
        tca: TCAInfo(detectedVersion: nil, dialect: .macro)
      ),
      modules: discovery.modules,
      nodes: result.nodes,
      edges: result.edges,
      sharedStorages: result.sharedStorages,
      diagnostics: result.diagnostics
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try? encoder.encode(graph)
  }

  static func findViewerDist(override: String?) -> URL? {
    let fm = FileManager.default
    var candidates: [URL] = []
    if let override {
      candidates.append(URL(fileURLWithPath: override).standardizedFileURL)
    }
    candidates.append(URL(fileURLWithPath: "viewer/dist").standardizedFileURL)
    let binURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    candidates.append(binURL.appendingPathComponent("../viewer/dist").standardizedFileURL)
    candidates.append(binURL.appendingPathComponent("../../viewer/dist").standardizedFileURL)
    candidates.append(binURL.appendingPathComponent("viewer/dist").standardizedFileURL)

    for c in candidates {
      if fm.fileExists(atPath: c.appendingPathComponent("index.html").path) {
        return c
      }
    }
    return nil
  }

  static func printUsage() {
    let msg = """
    tca-graph — analyze a TCA Swift codebase and visualize it.

    Usage:
      tca-graph serve <path> [-p <port>] [--no-open] [--viewer <dist-path>]
      tca-graph analyze <path> [-o <file>]

    Examples:
      tca-graph serve ~/Code/MyApp
      tca-graph serve . --port 9000 --no-open
      tca-graph analyze . -o graph.json

    """
    FileHandle.standardError.write(Data(msg.utf8))
  }

  static func currentGitCommit(at url: URL) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "rev-parse", "--short", "HEAD"]
    process.currentDirectoryURL = url
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch { return nil }
    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let s = String(data: data, encoding: .utf8) ?? ""
    return s.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
