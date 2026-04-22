import Foundation

public struct Edge: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case scope
    case ifLet
    case ifCaseLet
    case forEach
    case combine
  }

  public let id: String
  public let sourceId: String
  public let targetId: String
  public let kind: Kind
  public let presentation: Bool
  public let statePath: String?
  public let actionPath: String?
  public let location: SourceLocation?

  public init(
    id: String,
    sourceId: String,
    targetId: String,
    kind: Kind,
    presentation: Bool = false,
    statePath: String? = nil,
    actionPath: String? = nil,
    location: SourceLocation? = nil
  ) {
    self.id = id
    self.sourceId = sourceId
    self.targetId = targetId
    self.kind = kind
    self.presentation = presentation
    self.statePath = statePath
    self.actionPath = actionPath
    self.location = location
  }
}
