import XCTest
@testable import TCAGraphParser
import TCAGraphModel

final class SharedStorageNormalizationTests: XCTestCase {

  // MARK: - Unit tests for classifyStorage

  func testAppStorageLiteral() {
    let (kind, key) = DeclarationIndexer.classifyStorage(#".appStorage("user_referral")"#)
    XCTAssertEqual(kind, .appStorage)
    XCTAssertEqual(key, "user_referral")
  }

  func testInMemoryLiteral() {
    let (kind, key) = DeclarationIndexer.classifyStorage(#".inMemory("fcm_token")"#)
    XCTAssertEqual(kind, .inMemory)
    XCTAssertEqual(key, "fcm_token")
  }

  func testFileStorageWithAppendingComponent() {
    let raw = #".fileStorage(.documentsDirectory.appending(component: "updateInfo.json"))"#
    let (kind, key) = DeclarationIndexer.classifyStorage(raw)
    XCTAssertEqual(kind, .fileStorage)
    XCTAssertEqual(key, "updateInfo.json")
  }

  func testFileStorageFallbackToDescriptor() {
    // No appending(component:), no string literal — key falls back to full arg expression.
    let raw = ".fileStorage(myCustomURL)"
    let (kind, key) = DeclarationIndexer.classifyStorage(raw)
    XCTAssertEqual(kind, .fileStorage)
    XCTAssertEqual(key, "myCustomURL")
  }

  func testOtherForNonFactoryDescriptor() {
    // e.g. @Shared(MySharedKey.default) — not a factory call.
    let raw = "MySharedKey.default"
    let (kind, key) = DeclarationIndexer.classifyStorage(raw)
    XCTAssertEqual(kind, .other)
    XCTAssertEqual(key, "MySharedKey.default")
  }

  // MARK: - Integration test — aggregates across reducers

  func testSharedStorageAggregatesAcrossReducers() throws {
    let fixtureURL = try XCTUnwrap(
      Bundle.module.url(
        forResource: "SharedTwoReducers.swift",
        withExtension: "fixture",
        subdirectory: "Fixtures"
      )
    )

    let result = DeclarationIndexer.index(
      files: [fixtureURL],
      fileToModule: [fixtureURL.path: "mod:TestFeature"]
    )

    XCTAssertEqual(Set(result.nodes.map(\.name)), ["FeatureA", "FeatureB"])

    let byID = Dictionary(uniqueKeysWithValues: result.sharedStorages.map { ($0.id, $0) })
    XCTAssertEqual(byID.count, 3, "Expected 3 distinct storages; got ids: \(byID.keys.sorted())")

    // user_referral is shared across both reducers → one SharedStorage with two references.
    let referral = try XCTUnwrap(byID["shared:appStorage:user_referral"])
    XCTAssertEqual(referral.kind, .appStorage)
    XCTAssertEqual(referral.key, "user_referral")
    XCTAssertEqual(referral.referencedBy.count, 2)
    XCTAssertEqual(
      Set(referral.referencedBy.map(\.nodeId)),
      ["node:TestFeature.FeatureA", "node:TestFeature.FeatureB"]
    )
    XCTAssertTrue(referral.referencedBy.allSatisfy { $0.fieldName == "referral" })

    // fcm_token only in FeatureA.
    let fcm = try XCTUnwrap(byID["shared:inMemory:fcm_token"])
    XCTAssertEqual(fcm.kind, .inMemory)
    XCTAssertEqual(fcm.referencedBy.count, 1)
    XCTAssertEqual(fcm.referencedBy.first?.nodeId, "node:TestFeature.FeatureA")

    // fileStorage only in FeatureB, key extracted from appending(component:).
    let file = try XCTUnwrap(byID["shared:fileStorage:updateInfo.json"])
    XCTAssertEqual(file.kind, .fileStorage)
    XCTAssertEqual(file.key, "updateInfo.json")
    XCTAssertEqual(file.referencedBy.count, 1)
    XCTAssertEqual(file.referencedBy.first?.nodeId, "node:TestFeature.FeatureB")
  }
}
