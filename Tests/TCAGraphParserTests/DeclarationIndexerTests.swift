import XCTest
@testable import TCAGraphParser
import TCAGraphModel

final class DeclarationIndexerTests: XCTestCase {

  func testSimpleFeature() throws {
    let fixtureURL = try XCTUnwrap(
      Bundle.module.url(forResource: "SimpleFeature.swift", withExtension: "fixture", subdirectory: "Fixtures")
    )

    let result = DeclarationIndexer.index(
      files: [fixtureURL],
      fileToModule: [fixtureURL.path: "mod:TestFeature"]
    )

    XCTAssertEqual(result.nodes.count, 1, "Expected one reducer in fixture")
    let node = try XCTUnwrap(result.nodes.first)

    XCTAssertEqual(node.name, "Counter")
    XCTAssertEqual(node.moduleId, "mod:TestFeature")
    XCTAssertEqual(node.tcaDialect, .macro)
    XCTAssertTrue(node.attributes.contains("@Reducer"))
    XCTAssertTrue(node.usesBinding, "Body contains BindingReducer()")

    let depKeys = node.dependencies.map(\.keyPath).sorted()
    XCTAssertEqual(depKeys, ["apiClient", "uuid"])

    let state = try XCTUnwrap(node.state)
    let sheetField = try XCTUnwrap(state.fields.first { $0.name == "sheet" })
    XCTAssertTrue(sheetField.presentation)
    XCTAssertEqual(sheetField.childRef, "Child")

    let action = try XCTUnwrap(node.action)
    XCTAssertTrue(action.protocols.contains("BindableAction"))
    XCTAssertTrue(action.protocols.contains("ViewAction"))

    let nestedNames = action.nestedEnums.map(\.name).sorted()
    XCTAssertEqual(nestedNames, ["Delegate", "View"])
  }

  func testParentChildEdges() throws {
    let fixtureURL = try XCTUnwrap(
      Bundle.module.url(forResource: "ParentChild.swift", withExtension: "fixture", subdirectory: "Fixtures")
    )

    let result = DeclarationIndexer.index(
      files: [fixtureURL],
      fileToModule: [fixtureURL.path: "mod:TestFeature"]
    )

    XCTAssertEqual(Set(result.nodes.map(\.name)), ["Child", "Parent", "Destination"])
    XCTAssertTrue(result.diagnostics.isEmpty, "Unexpected diagnostics: \(result.diagnostics)")

    let parentEdges = result.edges.filter { $0.sourceId.hasSuffix(".Parent") }
    // Expected: 1 scope + 2 ifLet + 1 forEach = 4 edges
    XCTAssertEqual(parentEdges.count, 4, "Parent edges: \(parentEdges.map { "\($0.kind) \($0.targetId)" })")

    let byKind = Dictionary(grouping: parentEdges, by: { $0.kind })
    XCTAssertEqual(byKind[.scope]?.count, 1)
    XCTAssertEqual(byKind[.ifLet]?.count, 2)
    XCTAssertEqual(byKind[.forEach]?.count, 1)

    // Presentation flag check: \.$presented should be marked presentation=true
    let presentationEdge = try XCTUnwrap(parentEdges.first { $0.presentation })
    XCTAssertEqual(presentationEdge.kind, .ifLet)
    XCTAssertTrue(presentationEdge.statePath?.contains("$") ?? false)

    // All parent edges resolve to Child
    for edge in parentEdges {
      XCTAssertTrue(edge.targetId.hasSuffix(".Child"), "Expected edge to resolve to Child, got \(edge.targetId)")
    }

    // Destination enum gives 2 ifCaseLet edges
    let destEdges = result.edges.filter { $0.sourceId.hasSuffix(".Destination") }
    XCTAssertEqual(destEdges.count, 2)
    XCTAssertTrue(destEdges.allSatisfy { $0.kind == .ifCaseLet })
    let destTargets = Set(destEdges.map(\.targetId).map { $0.components(separatedBy: ".").last ?? "" })
    XCTAssertEqual(destTargets, ["Child", "Parent"])
  }
}
