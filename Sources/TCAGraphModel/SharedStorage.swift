import Foundation

/// A `@Shared` storage descriptor aggregated across the whole codebase.
///
/// Every `@Shared(.appStorage("key"))` (or `.inMemory`, `.fileStorage`) that
/// references the same logical storage collapses into a single SharedStorage with
/// the list of reducers that reference it. This is what powers the "Shared state"
/// view in the viewer — it's the coupling surface that's invisible in the reducer
/// composition tree.
public struct SharedStorage: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case appStorage
    case inMemory
    case fileStorage
    case other
  }

  public struct Reference: Codable, Equatable, Sendable {
    public let nodeId: String
    public let fieldName: String

    public init(nodeId: String, fieldName: String) {
      self.nodeId = nodeId
      self.fieldName = fieldName
    }
  }

  public let id: String
  public let kind: Kind
  public let key: String
  public let rawDescriptor: String
  public let referencedBy: [Reference]

  public init(
    id: String,
    kind: Kind,
    key: String,
    rawDescriptor: String,
    referencedBy: [Reference]
  ) {
    self.id = id
    self.kind = kind
    self.key = key
    self.rawDescriptor = rawDescriptor
    self.referencedBy = referencedBy
  }
}
