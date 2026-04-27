import Foundation
import TCAGraphModel
import TCAGraphParser
import TCAGraphLinter

extension CLI {

  // MARK: - check

  static func runCheck(positional: [String]) {
    var rootPath = "."
    var configPath: String?
    var format: DiagnosticFormat = .text

    var i = 0
    while i < positional.count {
      let a = positional[i]
      if a == "--config" {
        guard i + 1 < positional.count else { dieMissing(a) }
        configPath = positional[i + 1]; i += 2; continue
      }
      if a == "--format" {
        guard i + 1 < positional.count else { dieMissing(a) }
        guard let f = DiagnosticFormat(rawValue: positional[i + 1]) else {
          let supported = DiagnosticFormat.allCases.map(\.rawValue).joined(separator: ", ")
          FileHandle.standardError.write(Data("Unknown --format \(positional[i + 1]); expected: \(supported)\n".utf8))
          exit(1)
        }
        format = f; i += 2; continue
      }
      if !a.hasPrefix("-") { rootPath = a }
      i += 1
    }

    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL

    let configURL: URL? = {
      if let configPath { return URL(fileURLWithPath: configPath).standardizedFileURL }
      return LinterConfig.defaultConfigURL(in: rootURL)
    }()

    let config: LinterConfig
    do {
      if let configURL {
        config = try LinterConfig.load(from: configURL)
        FileHandle.standardError.write(Data("Loaded config from \(configURL.path)\n".utf8))
      } else {
        config = .default
        FileHandle.standardError.write(Data("No .tca-graph.yml found — using built-in defaults.\n".utf8))
      }
    } catch {
      FileHandle.standardError.write(Data("Config error: \(error)\n".utf8))
      exit(1)
    }

    guard let graph = analyzeIntoGraph(rootURL: rootURL) else {
      FileHandle.standardError.write(Data("Analysis failed.\n".utf8))
      exit(1)
    }

    let result = Linter.lint(graph: graph, config: config)
    let rendered = DiagnosticFormatter.render(result.diagnostics, format: format)
    FileHandle.standardOutput.write(Data(rendered.utf8))
    exit(result.exitCode)
  }

  // MARK: - init-budgets

  static func runInitBudgets(positional: [String]) {
    var rootPath = "."
    var force = false

    var i = 0
    while i < positional.count {
      let a = positional[i]
      if a == "--force" { force = true; i += 1; continue }
      if !a.hasPrefix("-") { rootPath = a }
      i += 1
    }

    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let configURL = rootURL.appendingPathComponent(".tca-graph.yml")

    if FileManager.default.fileExists(atPath: configURL.path), !force {
      FileHandle.standardError.write(Data("\(configURL.path) already exists — pass --force to overwrite.\n".utf8))
      exit(1)
    }

    guard let graph = analyzeIntoGraph(rootURL: rootURL) else {
      FileHandle.standardError.write(Data("Analysis failed.\n".utf8))
      exit(1)
    }

    let snapshot = currentMaxBudgets(graph: graph)
    let yaml = renderBaselineYAML(snapshot: snapshot)
    do {
      try yaml.write(to: configURL, atomically: true, encoding: .utf8)
    } catch {
      FileHandle.standardError.write(Data("Could not write config: \(error.localizedDescription)\n".utf8))
      exit(1)
    }

    FileHandle.standardOutput.write(Data("Wrote baseline budgets to \(configURL.path)\n".utf8))
    FileHandle.standardOutput.write(Data("Run `tca-graph check \(rootURL.path)` to verify it stays clean.\n".utf8))
  }

  // MARK: - shared helpers

  /// Wraps `buildGraphJSON` and decodes back into a `Graph` so the linter can
  /// run on a typed value rather than re-parsing JSON. Reuses the analyze pipeline
  /// the existing serve and analyze commands use — single source of truth.
  static func analyzeIntoGraph(rootURL: URL) -> Graph? {
    guard let data = buildGraphJSON(rootURL: rootURL) else { return nil }
    return try? JSONDecoder().decode(Graph.self, from: data)
  }

  private static func currentMaxBudgets(graph: Graph) -> LinterConfig.Budgets {
    var maxFields = 0
    var maxActions = 0
    var maxChildren = 0
    var maxChain = 0
    var maxDestinationCases = 0

    var outgoingCount: [String: Int] = [:]
    for edge in graph.edges {
      outgoingCount[edge.sourceId, default: 0] += 1
    }

    for node in graph.nodes {
      let fields = node.state?.fields.count ?? 0
      let actionCases = node.action?.cases.count ?? 0
      let nestedCases = node.action?.nestedEnums.reduce(0) { $0 + $1.cases.count } ?? 0
      let actions = actionCases + nestedCases
      let children = outgoingCount[node.id] ?? 0
      let chain = node.chainDepthMax

      maxFields = max(maxFields, fields)
      maxActions = max(maxActions, actions)
      maxChildren = max(maxChildren, children)
      maxChain = max(maxChain, chain)
      if node.isEnumReducer {
        maxDestinationCases = max(maxDestinationCases, fields)
      }
    }

    return LinterConfig.Budgets(
      maxFieldsPerReducer: maxFields,
      maxActionsPerReducer: maxActions,
      maxChildrenPerReducer: maxChildren,
      maxChainDepth: maxChain,
      maxDestinationCases: maxDestinationCases
    )
  }

  private static func renderBaselineYAML(snapshot: LinterConfig.Budgets) -> String {
    """
    # Generated by `tca-graph init-budgets`. Adjust thresholds to enforce stricter
    # or looser architectural limits, and run `tca-graph check` to verify.
    #
    # Tip: keep these set to the current maximum so the codebase only gets better,
    # never worse — the standard Prettier / golangci-lint / SwiftLint pattern.

    budgets:
      max_fields_per_reducer: \(snapshot.maxFieldsPerReducer)
      max_actions_per_reducer: \(snapshot.maxActionsPerReducer)
      max_children_per_reducer: \(snapshot.maxChildrenPerReducer)
      max_chain_depth: \(snapshot.maxChainDepth)
      max_destination_cases: \(snapshot.maxDestinationCases)

    rules:
      cycle: error
      mutual_presentation: error
      destination_overflow: error
      deep_chain: error
      many_fields: warning
      many_actions: warning
      many_children: warning

    """
  }

  private static func dieMissing(_ flag: String) -> Never {
    FileHandle.standardError.write(Data("Missing value for \(flag)\n".utf8))
    exit(1)
  }
}
