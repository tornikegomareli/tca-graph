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
      Data("Indexed \(result.nodes.count) reducers, \(result.edges.count) edges, \(result.diagnostics.count) diagnostics\n".utf8)
    )

    let iso = ISO8601DateFormatter()
    let graph = Graph(
      generator: GeneratorInfo(name: "tca-graph", version: "0.1.0"),
      generatedAt: iso.string(from: Date()),
      source: Source(
        rootPath: rootURL.path,
        gitCommit: currentGitCommit(at: rootURL),
        tca: TCAInfo(detectedVersion: nil, dialect: .macro)
      ),
      modules: discovery.modules,
      nodes: result.nodes,
      edges: result.edges,
      diagnostics: result.diagnostics
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try? encoder.encode(graph)
  }

  static func printUsage() {
    let msg = """
    tca-graph — analyze a TCA Swift codebase and emit a graph JSON.

    Usage:
      tca-graph analyze <path> [-o <file>]

    Examples:
      tca-graph analyze .
      tca-graph analyze ../MyApp -o graph.json

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
