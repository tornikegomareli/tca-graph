import Foundation

public struct GeneratorInfo: Codable, Equatable, Sendable {
  public let name: String
  public let version: String

  public init(name: String, version: String) {
    self.name = name
    self.version = version
  }
}

public struct TCAInfo: Codable, Equatable, Sendable {
  public let detectedVersion: String?
  public let dialect: Node.Dialect

  public init(detectedVersion: String? = nil, dialect: Node.Dialect = .unknown) {
    self.detectedVersion = detectedVersion
    self.dialect = dialect
  }
}

public struct Source: Codable, Equatable, Sendable {
  public let rootPath: String
  public let gitCommit: String?
  public let tca: TCAInfo

  public init(rootPath: String, gitCommit: String? = nil, tca: TCAInfo = TCAInfo()) {
    self.rootPath = rootPath
    self.gitCommit = gitCommit
    self.tca = tca
  }
}

public struct Graph: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let generator: GeneratorInfo
  public let generatedAt: String
  public let source: Source
  public let modules: [Module]
  public let nodes: [Node]
  public let edges: [Edge]
  public let sharedStorages: [SharedStorage]
  public let diagnostics: [Diagnostic]

  public init(
    schemaVersion: String = "0.1.0",
    generator: GeneratorInfo,
    generatedAt: String,
    source: Source,
    modules: [Module],
    nodes: [Node],
    edges: [Edge] = [],
    sharedStorages: [SharedStorage] = [],
    diagnostics: [Diagnostic] = []
  ) {
    self.schemaVersion = schemaVersion
    self.generator = generator
    self.generatedAt = generatedAt
    self.source = source
    self.modules = modules
    self.nodes = nodes
    self.edges = edges
    self.sharedStorages = sharedStorages
    self.diagnostics = diagnostics
  }
}
