import Foundation

public struct Module: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case spmTarget
    case folder
    case xcodeTarget
  }

  public let id: String
  public let name: String
  public let kind: Kind
  public let path: String
  public let packageManifest: String?

  public init(id: String, name: String, kind: Kind, path: String, packageManifest: String? = nil) {
    self.id = id
    self.name = name
    self.kind = kind
    self.path = path
    self.packageManifest = packageManifest
  }
}
