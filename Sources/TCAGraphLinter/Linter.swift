import Foundation
import TCAGraphModel

/// Runs the linter pass over a fully-analyzed graph. Combines budget breaches
/// (already detected by the parser as `ReducerRisk` records) with new graph
/// analyses (cycles, mutual presentation) and emits diagnostics filtered by the
/// user's `LinterConfig`.
public enum Linter {

  public struct Result {
    public let diagnostics: [LinterDiagnostic]
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
    public var hasWarnings: Bool { diagnostics.contains { $0.severity == .warning } }

    /// Conventional CI exit code: 0 clean, 1 warnings only, 2 errors.
    public var exitCode: Int32 {
      if hasErrors { return 2 }
      if hasWarnings { return 1 }
      return 0
    }

    public init(diagnostics: [LinterDiagnostic]) {
      self.diagnostics = diagnostics
    }
  }

  public static func lint(graph: Graph, config: LinterConfig) -> Result {
    var diagnostics: [LinterDiagnostic] = []
    let nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })

    // 1. Budget breaches surfaced from per-reducer metrics. Re-evaluate against
    //    the user's configured budgets so a tightened `.tca-graph.yml` still fires.
    var outgoingCount: [String: Int] = [:]
    for edge in graph.edges {
      outgoingCount[edge.sourceId, default: 0] += 1
    }
    for node in graph.nodes {
      diagnostics.append(contentsOf: budgetDiagnostics(
        for: node,
        children: outgoingCount[node.id] ?? 0,
        budgets: config.budgets,
        config: config
      ))
    }

    // 2. Graph-level cycles.
    let cycles = CycleDetector.cycles(in: graph.nodes, edges: graph.edges)
    for cycle in cycles {
      let names = cycle.map { nodesByID[$0]?.name ?? $0 }
      let firstNode = cycle.first.flatMap { nodesByID[$0] }
      diagnostics.append(
        LinterDiagnostic(
          rule: .cycle,
          severity: config.severity(for: .cycle),
          message: "Cycle in reducer composition: \(names.joined(separator: " → ")) → \(names.first ?? "")",
          nodeId: cycle.first,
          location: firstNode?.location ?? unknownLocation
        )
      )
    }

    // 3. Mutual presentation — A presents B and B presents A.
    let mutuals = CycleDetector.mutualPresentations(in: graph.edges)
    for (aID, bID) in mutuals {
      let aName = nodesByID[aID]?.name ?? aID
      let bName = nodesByID[bID]?.name ?? bID
      diagnostics.append(
        LinterDiagnostic(
          rule: .mutualPresentation,
          severity: config.severity(for: .mutualPresentation),
          message: "\(aName) and \(bName) present each other modally — modal-loop hazard.",
          nodeId: aID,
          location: nodesByID[aID]?.location ?? unknownLocation
        )
      )
    }

    return Result(diagnostics: diagnostics)
  }

  // MARK: - Budget breach mapping

  /// Re-evaluate the metrics that the parser already computed against the user's
  /// configured budget. The parser's defaults match `LinterConfig.Budgets.default`,
  /// so when the config matches defaults this just mirrors `node.risks`. When the
  /// user has tightened a budget, the new threshold takes precedence and the parser's
  /// pre-computed risk is ignored in favor of a fresh comparison.
  private static func budgetDiagnostics(
    for node: Node,
    children: Int,
    budgets: LinterConfig.Budgets,
    config: LinterConfig
  ) -> [LinterDiagnostic] {
    var out: [LinterDiagnostic] = []
    let fields = node.state?.fields.count ?? 0
    let actionCases = node.action?.cases.count ?? 0
    let nestedCases = node.action?.nestedEnums.reduce(0) { $0 + $1.cases.count } ?? 0
    let actions = actionCases + nestedCases
    let chainDepth = node.chainDepthMax

    if fields > budgets.maxFieldsPerReducer {
      out.append(make(
        .manyFields, config: config, node: node,
        message: "State has \(fields) fields — budget is \(budgets.maxFieldsPerReducer)."
      ))
    }
    if actions > budgets.maxActionsPerReducer {
      out.append(make(
        .manyActions, config: config, node: node,
        message: "Action enum exposes \(actions) cases — budget is \(budgets.maxActionsPerReducer)."
      ))
    }
    if children > budgets.maxChildrenPerReducer {
      out.append(make(
        .manyChildren, config: config, node: node,
        message: "Reducer composes \(children) children — budget is \(budgets.maxChildrenPerReducer)."
      ))
    }
    if chainDepth > budgets.maxChainDepth {
      out.append(make(
        .deepChain, config: config, node: node,
        message: "Modifier-chain depth \(chainDepth) — budget is \(budgets.maxChainDepth)."
      ))
    }
    if node.isEnumReducer {
      let cases = fields // synthesized from enum cases
      if cases > budgets.maxDestinationCases {
        out.append(make(
          .destinationOverflow, config: config, node: node,
          message: "Destination enum has \(cases) cases — budget is \(budgets.maxDestinationCases)."
        ))
      }
    }
    return out
  }

  private static func make(
    _ rule: LinterDiagnostic.Rule,
    config: LinterConfig,
    node: Node,
    message: String
  ) -> LinterDiagnostic {
    LinterDiagnostic(
      rule: rule,
      severity: config.severity(for: rule),
      message: message,
      nodeId: node.id,
      location: node.location
    )
  }

  private static let unknownLocation = SourceLocation(file: "<unknown>", line: 0, column: 0)
}
