import XCTest
@testable import TCAGraphLinter
import TCAGraphModel

final class CycleDetectorTests: XCTestCase {

  // MARK: - Cycles

  func testNoCycleInLinearChain() {
    // A → B → C
    let nodes = [n("A"), n("B"), n("C")]
    let edges = [e("A", "B"), e("B", "C")]
    XCTAssertTrue(CycleDetector.cycles(in: nodes, edges: edges).isEmpty)
  }

  func testNoCycleInTree() {
    // A → B, A → C, B → D
    let nodes = [n("A"), n("B"), n("C"), n("D")]
    let edges = [e("A", "B"), e("A", "C"), e("B", "D")]
    XCTAssertTrue(CycleDetector.cycles(in: nodes, edges: edges).isEmpty)
  }

  func testDetectsSimpleTwoCycle() {
    // A → B, B → A
    let nodes = [n("A"), n("B")]
    let edges = [e("A", "B"), e("B", "A")]
    let cycles = CycleDetector.cycles(in: nodes, edges: edges)
    XCTAssertEqual(cycles.count, 1)
    XCTAssertEqual(Set(cycles[0]), ["A", "B"])
  }

  func testDetectsThreeCycle() {
    // A → B → C → A
    let nodes = [n("A"), n("B"), n("C")]
    let edges = [e("A", "B"), e("B", "C"), e("C", "A")]
    let cycles = CycleDetector.cycles(in: nodes, edges: edges)
    XCTAssertEqual(cycles.count, 1)
    XCTAssertEqual(Set(cycles[0]), ["A", "B", "C"])
  }

  func testDeduplicatesSameCycleReachableFromMultipleRoots() {
    // Root → A, Root → B; A → B → C → A
    // The cycle A→B→C is reachable from multiple paths but should report once.
    let nodes = [n("Root"), n("A"), n("B"), n("C")]
    let edges = [e("Root", "A"), e("Root", "B"), e("A", "B"), e("B", "C"), e("C", "A")]
    let cycles = CycleDetector.cycles(in: nodes, edges: edges)
    XCTAssertEqual(cycles.count, 1)
  }

  // MARK: - Mutual presentation

  func testNoMutualPresentationOnNonPresentationEdges() {
    // A and B compose each other, but not via @Presents.
    let edges = [e("A", "B", presentation: false), e("B", "A", presentation: false)]
    XCTAssertTrue(CycleDetector.mutualPresentations(in: edges).isEmpty)
  }

  func testDetectsMutualPresentation() {
    let edges = [e("A", "B", presentation: true), e("B", "A", presentation: true)]
    let pairs = CycleDetector.mutualPresentations(in: edges)
    XCTAssertEqual(pairs.count, 1)
    let pair = pairs[0]
    XCTAssertTrue(
      (pair.0 == "A" && pair.1 == "B") || (pair.0 == "B" && pair.1 == "A"),
      "Got \(pair)"
    )
  }

  func testIgnoresUnidirectionalPresentation() {
    // A presents B, but B does not present A.
    let edges = [e("A", "B", presentation: true), e("B", "A", presentation: false)]
    XCTAssertTrue(CycleDetector.mutualPresentations(in: edges).isEmpty)
  }

  // MARK: - Helpers

  private func n(_ id: String) -> Node {
    Node(
      id: id,
      name: id,
      moduleId: "mod:Test",
      location: SourceLocation(file: "Test.swift", line: 1, column: 1)
    )
  }

  private func e(_ source: String, _ target: String, presentation: Bool = false) -> Edge {
    Edge(
      id: "edge:\(source)→\(target)",
      sourceId: source,
      targetId: target,
      kind: .scope,
      presentation: presentation
    )
  }
}
