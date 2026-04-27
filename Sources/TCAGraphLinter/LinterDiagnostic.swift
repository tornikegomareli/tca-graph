import Foundation
import TCAGraphModel

/// One diagnostic produced by the linter. Maps cleanly to Xcode / GitHub Actions /
/// JUnit-style outputs via the formatters in `DiagnosticFormatter.swift`.
public struct LinterDiagnostic: Codable, Equatable, Sendable {
  public enum Severity: String, Codable, Sendable {
    case warning
    case error
  }

  public enum Rule: String, Codable, Sendable {
    // Budget breaches — counterparts to ReducerRisk kinds, surfaced as diagnostics.
    case manyFields
    case manyActions
    case manyChildren
    case deepChain
    case destinationOverflow
    // Pure graph analyses, new in 0.4.0.
    case cycle
    case mutualPresentation
    // Parser diagnostics surfaced through the linter so they fail `check` and
    // show up inline in Xcode / GitHub formats. Without these, an analysis run
    // that hit a parse error or unresolved reference would silently produce a
    // partial graph and the linter would lint that partial graph as if it were
    // complete.
    case parseError
    case unresolvedReference
    case ambiguousReference

    /// Default severity when the user hasn't overridden in `.tca-graph.yml`.
    public var defaultSeverity: Severity {
      switch self {
      case .cycle, .mutualPresentation, .destinationOverflow: return .error
      case .deepChain: return .error
      case .parseError: return .error
      case .manyFields, .manyActions, .manyChildren: return .warning
      case .unresolvedReference, .ambiguousReference: return .warning
      }
    }
  }

  public let rule: Rule
  public let severity: Severity
  public let message: String
  /// Reducer this diagnostic is attached to (when applicable).
  public let nodeId: String?
  /// File / line / col so Xcode and GitHub can render the diagnostic at a precise location.
  public let location: SourceLocation

  public init(
    rule: Rule,
    severity: Severity,
    message: String,
    nodeId: String?,
    location: SourceLocation
  ) {
    self.rule = rule
    self.severity = severity
    self.message = message
    self.nodeId = nodeId
    self.location = location
  }
}
