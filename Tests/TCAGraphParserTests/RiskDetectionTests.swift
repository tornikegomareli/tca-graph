import XCTest
@testable import TCAGraphParser
import TCAGraphModel

final class RiskDetectionTests: XCTestCase {

  // MARK: - Per-risk fixtures

  func testManyFieldsRiskFires() throws {
    let result = try indexFixture("ManyFields")
    let node = try XCTUnwrap(result.nodes.first { $0.name == "WideState" })

    XCTAssertEqual(node.state?.fields.count, 41)
    XCTAssertGreaterThan(node.complexityScore, 0)

    let risk = try XCTUnwrap(node.risks.first { $0.kind == .manyFields })
    XCTAssertEqual(risk.value, 41)
    XCTAssertEqual(risk.threshold, 40)
  }

  func testDeepChainRiskFires() throws {
    let result = try indexFixture("DeepChain")
    let parent = try XCTUnwrap(result.nodes.first { $0.name == "DeepChainParent" })

    XCTAssertGreaterThanOrEqual(parent.chainDepthMax, 5)

    let risk = try XCTUnwrap(parent.risks.first { $0.kind == .deepChain })
    XCTAssertGreaterThan(risk.value, risk.threshold)
    XCTAssertEqual(risk.threshold, 4)
  }

  func testDestinationOverflowRiskFires() throws {
    let result = try indexFixture("BigDestination")
    let dest = try XCTUnwrap(result.nodes.first { $0.name == "BigDestination" })

    XCTAssertEqual(dest.state?.kind, .enum)
    XCTAssertEqual(dest.state?.fields.count, 9)

    let risk = try XCTUnwrap(dest.risks.first { $0.kind == .destinationOverflow })
    XCTAssertEqual(risk.value, 9)
    XCTAssertEqual(risk.threshold, 8)
  }

  func testSimpleReducerHasZeroRisks() throws {
    let result = try indexFixture("SimpleFeature")
    let counter = try XCTUnwrap(result.nodes.first { $0.name == "Counter" })

    XCTAssertTrue(counter.risks.isEmpty)
    XCTAssertGreaterThan(counter.complexityScore, 0, "Even simple reducers should have a non-zero score")
  }

  // MARK: - Helpers

  private func indexFixture(_ name: String) throws -> IndexResult {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "\(name).swift",
        withExtension: "fixture",
        subdirectory: "Fixtures"
      )
    )
    return DeclarationIndexer.index(
      files: [url],
      fileToModule: [url.path: "mod:TestFeature"]
    )
  }
}
