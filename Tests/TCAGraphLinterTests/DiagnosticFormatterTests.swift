import XCTest
@testable import TCAGraphLinter
import TCAGraphModel

final class DiagnosticFormatterTests: XCTestCase {

  func testEmptyTextRendersClean() {
    let out = DiagnosticFormatter.render([], format: .text)
    XCTAssertTrue(out.contains("no architectural-budget violations"))
  }

  func testEmptyXcodeIsEmpty() {
    XCTAssertEqual(DiagnosticFormatter.render([], format: .xcode), "")
  }

  func testEmptyGitHubIsEmpty() {
    XCTAssertEqual(DiagnosticFormatter.render([], format: .github), "")
  }

  func testEmptyJSONIsEmptyArray() {
    XCTAssertEqual(DiagnosticFormatter.render([], format: .json).trimmingCharacters(in: .whitespacesAndNewlines), "[]")
  }

  func testXcodeFormatMatchesXcodeRunScriptParser() {
    // Xcode parses lines of the form: `<absolute path>:<line>:<col>: warning|error: <message>`
    let d = LinterDiagnostic(
      rule: .manyActions,
      severity: .warning,
      message: "Action enum exposes 33 cases — budget is 30.",
      nodeId: "node:F.MyReducer",
      location: SourceLocation(file: "/Users/me/MyReducer.swift", line: 12, column: 5)
    )
    let out = DiagnosticFormatter.render([d], format: .xcode)
    XCTAssertTrue(out.hasPrefix("/Users/me/MyReducer.swift:12:5: warning: "))
    XCTAssertTrue(out.contains("Action enum exposes 33 cases"))
    XCTAssertTrue(out.contains("(tca-graph: manyActions)"))
  }

  func testGitHubFormatProducesAnnotationLine() {
    // GitHub parses: `::warning file=...,line=N,col=M,title=...::message`
    let d = LinterDiagnostic(
      rule: .cycle,
      severity: .error,
      message: "Cycle: A → B → A",
      nodeId: "node:F.A",
      location: SourceLocation(file: "/repo/Foo.swift", line: 3, column: 1)
    )
    let out = DiagnosticFormatter.render([d], format: .github)
    XCTAssertTrue(out.hasPrefix("::error file=/repo/Foo.swift,line=3,col=1,title=tca-graph/cycle::"))
    XCTAssertTrue(out.contains("Cycle: A → B → A"))
  }

  func testTextFormatHasSummary() {
    let d1 = LinterDiagnostic(rule: .manyFields, severity: .warning, message: "many fields", nodeId: nil, location: SourceLocation(file: "x.swift", line: 1, column: 1))
    let d2 = LinterDiagnostic(rule: .cycle, severity: .error, message: "cycle", nodeId: nil, location: SourceLocation(file: "y.swift", line: 1, column: 1))
    let out = DiagnosticFormatter.render([d1, d2], format: .text)
    XCTAssertTrue(out.contains("1 error(s), 1 warning(s)"))
  }
}
