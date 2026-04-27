import Foundation
import Yams

/// User-configurable budgets and rule severities. Read from a project-local
/// `.tca-graph.yml` (or whatever path is passed via `--config`) and falls back
/// to research-backed defaults when fields are missing.
public struct LinterConfig: Equatable, Sendable {

  public struct Budgets: Equatable, Sendable {
    public var maxFieldsPerReducer: Int
    public var maxActionsPerReducer: Int
    public var maxChildrenPerReducer: Int
    public var maxChainDepth: Int
    public var maxDestinationCases: Int

    public init(
      maxFieldsPerReducer: Int,
      maxActionsPerReducer: Int,
      maxChildrenPerReducer: Int,
      maxChainDepth: Int,
      maxDestinationCases: Int
    ) {
      self.maxFieldsPerReducer = maxFieldsPerReducer
      self.maxActionsPerReducer = maxActionsPerReducer
      self.maxChildrenPerReducer = maxChildrenPerReducer
      self.maxChainDepth = maxChainDepth
      self.maxDestinationCases = maxDestinationCases
    }

    public static let `default` = Budgets(
      maxFieldsPerReducer: 40,
      maxActionsPerReducer: 30,
      maxChildrenPerReducer: 10,
      maxChainDepth: 4,
      maxDestinationCases: 8
    )
  }

  public var budgets: Budgets
  /// Per-rule severity overrides. Rules absent from this map fall back to
  /// `Rule.defaultSeverity`.
  public var ruleSeverities: [LinterDiagnostic.Rule: LinterDiagnostic.Severity]

  public init(
    budgets: Budgets,
    ruleSeverities: [LinterDiagnostic.Rule: LinterDiagnostic.Severity] = [:]
  ) {
    self.budgets = budgets
    self.ruleSeverities = ruleSeverities
  }

  public static let `default` = LinterConfig(
    budgets: .default,
    ruleSeverities: [:]
  )

  public func severity(for rule: LinterDiagnostic.Rule) -> LinterDiagnostic.Severity {
    ruleSeverities[rule] ?? rule.defaultSeverity
  }

  // MARK: - YAML loading

  public enum LoadError: Error, CustomStringConvertible {
    case fileNotReadable(URL, underlying: Error)
    case malformed(String)

    public var description: String {
      switch self {
      case .fileNotReadable(let url, let err):
        return "Could not read config at \(url.path): \(err.localizedDescription)"
      case .malformed(let msg):
        return "Malformed config: \(msg)"
      }
    }
  }

  /// Loads config from disk, returns defaults if the file does not exist.
  /// Throws if the file exists but cannot be parsed — surfaces user mistakes
  /// instead of silently falling back.
  public static func load(from url: URL) throws -> LinterConfig {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else { return .default }
    let raw: String
    do {
      raw = try String(contentsOf: url, encoding: .utf8)
    } catch {
      throw LoadError.fileNotReadable(url, underlying: error)
    }
    let parsed: Any?
    do {
      parsed = try Yams.load(yaml: raw)
    } catch {
      throw LoadError.malformed("YAML parse error: \(error.localizedDescription)")
    }
    guard let dict = parsed as? [String: Any] else {
      // An empty file is a valid no-op — same as missing.
      if parsed == nil { return .default }
      throw LoadError.malformed("Top level must be a mapping")
    }
    return try parse(dict)
  }

  /// Resolves the conventional config path for a project root: `.tca-graph.yml`,
  /// falling back to `.tca-graph.yaml`. Returns nil when neither exists.
  public static func defaultConfigURL(in projectRoot: URL) -> URL? {
    let fm = FileManager.default
    for name in [".tca-graph.yml", ".tca-graph.yaml"] {
      let candidate = projectRoot.appendingPathComponent(name)
      if fm.fileExists(atPath: candidate.path) { return candidate }
    }
    return nil
  }

  private static func parse(_ dict: [String: Any]) throws -> LinterConfig {
    var budgets = Budgets.default
    if let raw = dict["budgets"] as? [String: Any] {
      if let v = raw["max_fields_per_reducer"] as? Int { budgets.maxFieldsPerReducer = v }
      if let v = raw["max_actions_per_reducer"] as? Int { budgets.maxActionsPerReducer = v }
      if let v = raw["max_children_per_reducer"] as? Int { budgets.maxChildrenPerReducer = v }
      if let v = raw["max_chain_depth"] as? Int { budgets.maxChainDepth = v }
      if let v = raw["max_destination_cases"] as? Int { budgets.maxDestinationCases = v }
    }

    var ruleSeverities: [LinterDiagnostic.Rule: LinterDiagnostic.Severity] = [:]
    if let raw = dict["rules"] as? [String: Any] {
      for (ruleKey, value) in raw {
        guard let rule = ruleFromYAMLKey(ruleKey) else {
          throw LoadError.malformed("Unknown rule \"\(ruleKey)\"")
        }
        guard let str = value as? String,
              let severity = LinterDiagnostic.Severity(rawValue: str) else {
          throw LoadError.malformed("rules.\(ruleKey) must be \"warning\" or \"error\"")
        }
        ruleSeverities[rule] = severity
      }
    }

    return LinterConfig(budgets: budgets, ruleSeverities: ruleSeverities)
  }

  /// YAML keys are snake_case; `LinterDiagnostic.Rule` cases are camelCase.
  private static func ruleFromYAMLKey(_ key: String) -> LinterDiagnostic.Rule? {
    switch key {
    case "many_fields": return .manyFields
    case "many_actions": return .manyActions
    case "many_children": return .manyChildren
    case "deep_chain": return .deepChain
    case "destination_overflow": return .destinationOverflow
    case "cycle": return .cycle
    case "mutual_presentation": return .mutualPresentation
    default: return nil
    }
  }

  /// Inverse of `ruleFromYAMLKey` — for emitting baseline configs via init-budgets.
  public static func yamlKey(for rule: LinterDiagnostic.Rule) -> String {
    switch rule {
    case .manyFields: return "many_fields"
    case .manyActions: return "many_actions"
    case .manyChildren: return "many_children"
    case .deepChain: return "deep_chain"
    case .destinationOverflow: return "destination_overflow"
    case .cycle: return "cycle"
    case .mutualPresentation: return "mutual_presentation"
    }
  }
}
