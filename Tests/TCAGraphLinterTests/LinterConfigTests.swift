import XCTest
@testable import TCAGraphLinter

final class LinterConfigTests: XCTestCase {

  func testDefaultsAreUsedWhenFileMissing() throws {
    let url = URL(fileURLWithPath: "/tmp/nonexistent-tca-graph-config-\(UUID().uuidString).yml")
    let config = try LinterConfig.load(from: url)
    XCTAssertEqual(config.budgets, .default)
    XCTAssertTrue(config.ruleSeverities.isEmpty)
  }

  func testParsesBudgetsAndRuleSeverities() throws {
    let yaml = """
    budgets:
      max_fields_per_reducer: 25
      max_actions_per_reducer: 20
      max_destination_cases: 6
    rules:
      cycle: error
      many_fields: warning
    """
    let url = try writeTemp(yaml)
    let config = try LinterConfig.load(from: url)

    XCTAssertEqual(config.budgets.maxFieldsPerReducer, 25)
    XCTAssertEqual(config.budgets.maxActionsPerReducer, 20)
    XCTAssertEqual(config.budgets.maxDestinationCases, 6)
    // Unspecified budgets keep their default values.
    XCTAssertEqual(config.budgets.maxChildrenPerReducer, LinterConfig.Budgets.default.maxChildrenPerReducer)
    XCTAssertEqual(config.budgets.maxChainDepth, LinterConfig.Budgets.default.maxChainDepth)

    XCTAssertEqual(config.severity(for: .cycle), .error)
    XCTAssertEqual(config.severity(for: .manyFields), .warning)
    // Rules not in the file fall back to their default severity.
    XCTAssertEqual(config.severity(for: .deepChain), LinterDiagnostic.Rule.deepChain.defaultSeverity)
  }

  func testRejectsUnknownRule() throws {
    let yaml = """
    rules:
      sky_is_falling: error
    """
    let url = try writeTemp(yaml)
    XCTAssertThrowsError(try LinterConfig.load(from: url)) { error in
      guard case LinterConfig.LoadError.malformed(let msg) = error else {
        XCTFail("Expected malformed; got \(error)")
        return
      }
      XCTAssertTrue(msg.contains("sky_is_falling"))
    }
  }

  func testRejectsBadSeverity() throws {
    let yaml = """
    rules:
      cycle: critical
    """
    let url = try writeTemp(yaml)
    XCTAssertThrowsError(try LinterConfig.load(from: url))
  }

  func testEmptyFileReturnsDefaults() throws {
    let url = try writeTemp("")
    let config = try LinterConfig.load(from: url)
    XCTAssertEqual(config.budgets, .default)
  }

  // MARK: - Helpers

  private func writeTemp(_ contents: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("tca-graph-test-\(UUID().uuidString).yml")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}
