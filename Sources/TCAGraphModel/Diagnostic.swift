import Foundation

public struct Diagnostic: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case parseError
    case unresolvedChild
    case ambiguousReference
    case unknownBodyElement
  }

  public let kind: Kind
  public let message: String
  public let location: SourceLocation?

  public init(kind: Kind, message: String, location: SourceLocation? = nil) {
    self.kind = kind
    self.message = message
    self.location = location
  }
}
