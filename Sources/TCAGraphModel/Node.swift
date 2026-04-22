import Foundation

public struct StateField: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case regular
    case shared
  }

  public let name: String
  public let type: String
  public let optional: Bool
  public let collection: Bool
  public let presentation: Bool
  public let kind: Kind
  public let storage: String?
  public let childRef: String?

  public init(
    name: String,
    type: String,
    optional: Bool = false,
    collection: Bool = false,
    presentation: Bool = false,
    kind: Kind = .regular,
    storage: String? = nil,
    childRef: String? = nil
  ) {
    self.name = name
    self.type = type
    self.optional = optional
    self.collection = collection
    self.presentation = presentation
    self.kind = kind
    self.storage = storage
    self.childRef = childRef
  }
}

public struct ActionCase: Codable, Equatable, Sendable {
  public let name: String
  public let payload: [String]

  public init(name: String, payload: [String] = []) {
    self.name = name
    self.payload = payload
  }
}

public struct NestedEnum: Codable, Equatable, Sendable {
  public let name: String
  public let cases: [ActionCase]

  public init(name: String, cases: [ActionCase]) {
    self.name = name
    self.cases = cases
  }
}

public struct StateDecl: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case `struct`
    case `enum`
  }

  public let typeName: String
  public let kind: Kind
  public let protocols: [String]
  public let fields: [StateField]

  public init(typeName: String, kind: Kind, protocols: [String], fields: [StateField]) {
    self.typeName = typeName
    self.kind = kind
    self.protocols = protocols
    self.fields = fields
  }
}

public struct ActionDecl: Codable, Equatable, Sendable {
  public let typeName: String
  public let protocols: [String]
  public let cases: [ActionCase]
  public let nestedEnums: [NestedEnum]

  public init(typeName: String, protocols: [String], cases: [ActionCase], nestedEnums: [NestedEnum]) {
    self.typeName = typeName
    self.protocols = protocols
    self.cases = cases
    self.nestedEnums = nestedEnums
  }
}

public struct DependencyRef: Codable, Equatable, Sendable {
  public let keyPath: String
  public let typeName: String?

  public init(keyPath: String, typeName: String? = nil) {
    self.keyPath = keyPath
    self.typeName = typeName
  }
}

public struct Node: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case reducer
  }

  public enum Dialect: String, Codable, Sendable {
    case macro
    case `protocol`
    case legacy
    case unknown
  }

  public let id: String
  public let name: String
  public let kind: Kind
  public let moduleId: String
  public let location: SourceLocation
  public let tcaDialect: Dialect
  public let attributes: [String]
  public let usesBinding: Bool
  public let state: StateDecl?
  public let action: ActionDecl?
  public let dependencies: [DependencyRef]

  public init(
    id: String,
    name: String,
    kind: Kind = .reducer,
    moduleId: String,
    location: SourceLocation,
    tcaDialect: Dialect = .unknown,
    attributes: [String] = [],
    usesBinding: Bool = false,
    state: StateDecl? = nil,
    action: ActionDecl? = nil,
    dependencies: [DependencyRef] = []
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.moduleId = moduleId
    self.location = location
    self.tcaDialect = tcaDialect
    self.attributes = attributes
    self.usesBinding = usesBinding
    self.state = state
    self.action = action
    self.dependencies = dependencies
  }
}
