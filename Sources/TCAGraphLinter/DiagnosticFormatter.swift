import Foundation

public enum DiagnosticFormat: String, CaseIterable, Sendable {
  case text
  case xcode
  case github
  case json
}

public enum DiagnosticFormatter {

  /// Render diagnostics in the requested format. The output is always trailing-
  /// newline-terminated unless the diagnostic list is empty.
  public static func render(_ diagnostics: [LinterDiagnostic], format: DiagnosticFormat) -> String {
    if diagnostics.isEmpty {
      switch format {
      case .text:   return "tca-graph: no architectural-budget violations.\n"
      case .xcode:  return ""
      case .github: return ""
      case .json:   return "[]\n"
      }
    }
    switch format {
    case .text:   return renderText(diagnostics)
    case .xcode:  return renderXcode(diagnostics)
    case .github: return renderGitHub(diagnostics)
    case .json:   return renderJSON(diagnostics)
    }
  }

  // MARK: - Text (human-readable)

  private static func renderText(_ diagnostics: [LinterDiagnostic]) -> String {
    let warnings = diagnostics.filter { $0.severity == .warning }.count
    let errors = diagnostics.filter { $0.severity == .error }.count
    var lines: [String] = []
    for d in diagnostics {
      let icon = d.severity == .error ? "✘" : "⚠"
      let location = "\(shortenPath(d.location.file)):\(d.location.line)"
      lines.append("\(icon) [\(d.severity.rawValue)] \(d.rule.rawValue): \(d.message)")
      lines.append("   \(location)")
    }
    lines.append("")
    lines.append("\(errors) error(s), \(warnings) warning(s).")
    return lines.joined(separator: "\n") + "\n"
  }

  // MARK: - Xcode (Run Script Build Phase)

  /// Format Xcode parses for inline diagnostics:
  ///   `<absolute-path>:<line>:<col>: warning|error: <message>`
  /// Run Script Build Phases that emit this on stdout/stderr get rendered as
  /// regular Xcode warnings/errors — clickable, navigable, the works.
  private static func renderXcode(_ diagnostics: [LinterDiagnostic]) -> String {
    diagnostics.map { d in
      "\(d.location.file):\(d.location.line):\(d.location.column): \(d.severity.rawValue): \(d.message) (tca-graph: \(d.rule.rawValue))"
    }.joined(separator: "\n") + "\n"
  }

  // MARK: - GitHub Actions annotations

  /// Format GitHub renders as PR annotations and inline file annotations:
  ///   `::warning file=<path>,line=<N>,col=<M>::<message>`
  /// Emit on stdout from a GitHub Actions step.
  private static func renderGitHub(_ diagnostics: [LinterDiagnostic]) -> String {
    diagnostics.map { d in
      let level = d.severity == .error ? "error" : "warning"
      let title = "tca-graph/\(d.rule.rawValue)"
      return "::\(level) file=\(d.location.file),line=\(d.location.line),col=\(d.location.column),title=\(title)::\(d.message)"
    }.joined(separator: "\n") + "\n"
  }

  // MARK: - JSON

  private static func renderJSON(_ diagnostics: [LinterDiagnostic]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(diagnostics),
          let string = String(data: data, encoding: .utf8) else {
      return "[]\n"
    }
    return string + "\n"
  }

  // MARK: - Helpers

  /// Trim absolute paths to the trailing two segments for terminal rendering only.
  /// Xcode and GitHub formatters keep the full path.
  private static func shortenPath(_ path: String) -> String {
    let parts = path.split(separator: "/")
    return parts.suffix(2).joined(separator: "/")
  }
}
