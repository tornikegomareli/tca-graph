import Foundation
import SwiftSyntax
import SwiftParser
import TCAGraphModel

public struct IndexResult {
  public var nodes: [Node]
  public var edges: [Edge]
  public var diagnostics: [Diagnostic]
}

struct ExtensionContribution {
  var state: StateDecl?
  var action: ActionDecl?
  var dependencies: [DependencyRef] = []
  var usesBindingMention = false
}

/// Emitted by the body walker before target names are resolved against the node index.
struct RawEdge {
  var sourceNodeID: String
  var filePath: String
  var targetName: String
  var kind: Edge.Kind
  var presentation: Bool
  var statePath: String?
  var actionPath: String?
  var location: TCAGraphModel.SourceLocation
}

public enum DeclarationIndexer {

  public static func index(
    files: [URL],
    fileToModule: [String: String],
    fallbackModule: String = "mod:Unknown"
  ) -> IndexResult {
    var nodes: [Node] = []
    var diagnostics: [Diagnostic] = []
    var extensions: [String: [ExtensionContribution]] = [:]
    var rawEdges: [RawEdge] = []
    var importsByFile: [String: [String]] = [:]

    for file in files {
      let moduleID = fileToModule[file.path] ?? fallbackModule
      do {
        let source = try String(contentsOf: file, encoding: .utf8)
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file.path, tree: tree)
        let visitor = ReducerVisitor(
          filePath: file.path,
          moduleID: moduleID,
          converter: converter
        )
        visitor.walk(tree)
        nodes.append(contentsOf: visitor.nodes)
        diagnostics.append(contentsOf: visitor.diagnostics)
        rawEdges.append(contentsOf: visitor.rawEdges)
        importsByFile[file.path] = visitor.imports
        for (key, contribs) in visitor.extensions {
          extensions[key, default: []].append(contentsOf: contribs)
        }
      } catch {
        diagnostics.append(
          Diagnostic(
            kind: .parseError,
            message: "Failed to read \(file.path): \(error.localizedDescription)",
            location: TCAGraphModel.SourceLocation(file: file.path, line: 0, column: 0)
          )
        )
      }
    }

    // Merge extension contributions into the corresponding reducer nodes.
    nodes = nodes.map { node in mergeExtensions(into: node, from: extensions) }

    // Resolve raw edges into real edges.
    let (edges, resolveDiagnostics) = resolveEdges(
      rawEdges: rawEdges,
      nodes: nodes,
      importsByFile: importsByFile
    )
    diagnostics.append(contentsOf: resolveDiagnostics)

    return IndexResult(nodes: nodes, edges: edges, diagnostics: diagnostics)
  }

  private static func mergeExtensions(
    into node: Node,
    from extensions: [String: [ExtensionContribution]]
  ) -> Node {
    // Extensions are keyed by "moduleID:typeName" so same-named reducers in different
    // modules never cross-contaminate each other's State / Action / dependencies.
    let contribs = extensions["\(node.moduleId):\(node.name)"] ?? []
    guard !contribs.isEmpty else { return node }

    var state = node.state
    var action = node.action
    var deps = node.dependencies
    var usesBinding = node.usesBinding

    for c in contribs {
      if state == nil { state = c.state }
      if action == nil { action = c.action }
      deps.append(contentsOf: c.dependencies)
      if c.usesBindingMention { usesBinding = true }
    }

    return Node(
      id: node.id,
      name: node.name,
      kind: node.kind,
      moduleId: node.moduleId,
      location: node.location,
      tcaDialect: node.tcaDialect,
      attributes: node.attributes,
      usesBinding: usesBinding,
      state: state,
      action: action,
      dependencies: deps
    )
  }

  // MARK: - Edge resolution

  private static func resolveEdges(
    rawEdges: [RawEdge],
    nodes: [Node],
    importsByFile: [String: [String]]
  ) -> ([Edge], [Diagnostic]) {
    // Build indexes: simple name → [Node], module name ("DashboardFeature") → [Node]
    var byName: [String: [Node]] = [:]
    for node in nodes {
      byName[node.name, default: []].append(node)
    }
    let moduleIDByName: [String: String] = Dictionary(
      uniqueKeysWithValues: nodes.map { ($0.id, $0.moduleId) }
    )
    _ = moduleIDByName

    var edges: [Edge] = []
    var diagnostics: [Diagnostic] = []
    var edgeCounter = 0

    for raw in rawEdges {
      edgeCounter += 1
      let edgeID = "edge:\(edgeCounter)"

      let candidates = byName[raw.targetName] ?? []
      let sourceModule = nodes.first(where: { $0.id == raw.sourceNodeID })?.moduleId

      let resolved: Node?
      if candidates.isEmpty {
        resolved = nil
      } else if candidates.count == 1 {
        resolved = candidates[0]
      } else {
        // Prefer same-module match, else an imported one.
        let imports = importsByFile[raw.filePath] ?? []
        if let sameModule = candidates.first(where: { $0.moduleId == sourceModule }) {
          resolved = sameModule
        } else if let imported = candidates.first(where: { imports.contains(moduleName(from: $0.moduleId)) }) {
          resolved = imported
        } else {
          resolved = candidates[0]
          diagnostics.append(
            Diagnostic(
              kind: .ambiguousReference,
              message: "\(raw.targetName) matches \(candidates.count) reducers; picked \(candidates[0].id)",
              location: raw.location
            )
          )
        }
      }

      if let resolved {
        edges.append(
          Edge(
            id: edgeID,
            sourceId: raw.sourceNodeID,
            targetId: resolved.id,
            kind: raw.kind,
            presentation: raw.presentation,
            statePath: raw.statePath,
            actionPath: raw.actionPath,
            location: raw.location
          )
        )
      } else {
        diagnostics.append(
          Diagnostic(
            kind: .unresolvedChild,
            message: "Could not resolve reducer '\(raw.targetName)' referenced from \(raw.sourceNodeID)",
            location: raw.location
          )
        )
        edges.append(
          Edge(
            id: edgeID,
            sourceId: raw.sourceNodeID,
            targetId: "node:unresolved.\(raw.targetName)",
            kind: raw.kind,
            presentation: raw.presentation,
            statePath: raw.statePath,
            actionPath: raw.actionPath,
            location: raw.location
          )
        )
      }
    }

    return (edges, diagnostics)
  }

  private static func moduleName(from moduleID: String) -> String {
    moduleID.hasPrefix("mod:") ? String(moduleID.dropFirst(4)) : moduleID
  }
}

// MARK: - Visitor

final class ReducerVisitor: SyntaxVisitor {
  let filePath: String
  let moduleID: String
  let converter: SourceLocationConverter
  var nodes: [Node] = []
  var diagnostics: [Diagnostic] = []
  var extensions: [String: [ExtensionContribution]] = [:]
  var rawEdges: [RawEdge] = []
  var imports: [String] = []

  init(filePath: String, moduleID: String, converter: SourceLocationConverter) {
    self.filePath = filePath
    self.moduleID = moduleID
    self.converter = converter
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    let path = node.path.map { $0.name.text }.joined(separator: ".")
    if !path.isEmpty {
      imports.append(path)
    }
    return .skipChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    if let (dialect, attributeNames) = detectReducer(attributes: node.attributes, inheritance: node.inheritanceClause) {
      let built = buildNode(
        name: node.name.text,
        attributes: attributeNames,
        dialect: dialect,
        position: node.name.positionAfterSkippingLeadingTrivia,
        members: node.memberBlock.members,
        isEnumReducer: false
      )
      nodes.append(built)
    }
    return .visitChildren
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    if let (dialect, attributeNames) = detectReducer(attributes: node.attributes, inheritance: node.inheritanceClause) {
      let built = buildNode(
        name: node.name.text,
        attributes: attributeNames,
        dialect: dialect,
        position: node.name.positionAfterSkippingLeadingTrivia,
        members: node.memberBlock.members,
        isEnumReducer: true
      )
      nodes.append(built)
    }
    return .visitChildren
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    let extendedName = node.extendedType.trimmedDescription
      .split(separator: ".").last.map(String.init) ?? ""
    guard !extendedName.isEmpty else { return .skipChildren }

    var contrib = ExtensionContribution()
    var didContribute = false

    for member in node.memberBlock.members {
      if let varDecl = member.decl.as(VariableDeclSyntax.self) {
        if let dep = extractDependency(varDecl) {
          contrib.dependencies.append(dep)
          didContribute = true
          continue
        }
        if varDecl.isBodyProperty {
          if varDecl.description.contains("BindingReducer()") {
            contrib.usesBindingMention = true
            didContribute = true
          }
          // Also walk body for edges if body is in an extension.
          walkBody(
            varDecl: varDecl,
            sourceName: extendedName,
            sourceNodeIDGuess: "node:\(moduleNameOnly()).\(extendedName)"
          )
        }
      }
      if let nested = member.decl.as(StructDeclSyntax.self), nested.name.text == "State" {
        contrib.state = extractStateStruct(nested)
        didContribute = true
      } else if let nested = member.decl.as(EnumDeclSyntax.self), nested.name.text == "State" {
        contrib.state = extractStateEnum(nested)
        didContribute = true
      } else if let nested = member.decl.as(EnumDeclSyntax.self), nested.name.text == "Action" {
        contrib.action = extractAction(nested)
        didContribute = true
      }
    }

    if didContribute {
      extensions["\(moduleID):\(extendedName)", default: []].append(contrib)
    }
    return .skipChildren
  }

  // MARK: - Reducer detection

  private func detectReducer(
    attributes: AttributeListSyntax,
    inheritance: InheritanceClauseSyntax?
  ) -> (Node.Dialect, [String])? {
    var hasReducerMacro = false
    var names: [String] = []
    for attr in attributes {
      guard case .attribute(let a) = attr else { continue }
      let name = a.attributeName.trimmedDescription
      names.append("@\(name)")
      if name == "Reducer" { hasReducerMacro = true }
    }
    if hasReducerMacro {
      return (.macro, names)
    }
    if let inheritance {
      for inherited in inheritance.inheritedTypes {
        let n = inherited.type.trimmedDescription
        if n == "Reducer" || n == "ReducerProtocol" {
          return (.protocol, names)
        }
      }
    }
    return nil
  }

  // MARK: - Node construction

  private func buildNode(
    name: String,
    attributes: [String],
    dialect: Node.Dialect,
    position: AbsolutePosition,
    members: MemberBlockItemListSyntax,
    isEnumReducer: Bool
  ) -> Node {
    let location = sourceLocation(for: position)
    let nodeID = "node:\(moduleNameOnly()).\(name)"

    var state: StateDecl?
    var action: ActionDecl?
    var dependencies: [DependencyRef] = []
    var usesBinding = false

    if isEnumReducer {
      // Synthesize State and Action from enum cases; emit ifCaseLet edges per case payload.
      var fields: [StateField] = []
      var cases: [ActionCase] = []
      for member in members {
        guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
        for element in caseDecl.elements {
          let caseName = element.name.text
          let payload = element.parameterClause?.parameters.map { $0.type.trimmedDescription } ?? []
          let payloadType = payload.joined(separator: ", ")
          fields.append(
            StateField(
              name: caseName,
              type: payloadType.isEmpty ? "()" : payloadType,
              childRef: payload.first.flatMap(extractChildRefFromEnumPayload)
            )
          )
          cases.append(ActionCase(name: caseName, payload: payload))

          if let target = payload.first.flatMap(extractChildRefFromEnumPayload) {
            let caseLocation = sourceLocation(for: element.positionAfterSkippingLeadingTrivia)
            rawEdges.append(
              RawEdge(
                sourceNodeID: nodeID,
                filePath: filePath,
                targetName: target,
                kind: .ifCaseLet,
                presentation: false,
                statePath: caseName,
                actionPath: caseName,
                location: caseLocation
              )
            )
          }
        }
      }
      state = StateDecl(typeName: "State", kind: .enum, protocols: [], fields: fields)
      action = ActionDecl(typeName: "Action", protocols: [], cases: cases, nestedEnums: [])
    } else {
      for member in members {
        if let varDecl = member.decl.as(VariableDeclSyntax.self),
           let dep = extractDependency(varDecl) {
          dependencies.append(dep)
          continue
        }

        if let nested = member.decl.as(StructDeclSyntax.self), nested.name.text == "State" {
          state = extractStateStruct(nested)
        } else if let nested = member.decl.as(EnumDeclSyntax.self), nested.name.text == "State" {
          state = extractStateEnum(nested)
        } else if let nested = member.decl.as(EnumDeclSyntax.self), nested.name.text == "Action" {
          action = extractAction(nested)
        }

        if let varDecl = member.decl.as(VariableDeclSyntax.self),
           varDecl.isBodyProperty {
          if varDecl.description.contains("BindingReducer()") {
            usesBinding = true
          }
          walkBody(varDecl: varDecl, sourceName: name, sourceNodeIDGuess: nodeID)
        }
      }
    }

    return Node(
      id: nodeID,
      name: name,
      moduleId: moduleID,
      location: location,
      tcaDialect: dialect,
      attributes: attributes,
      usesBinding: usesBinding,
      state: state,
      action: action,
      dependencies: dependencies
    )
  }

  private func moduleNameOnly() -> String {
    if moduleID.hasPrefix("mod:") {
      return String(moduleID.dropFirst(4))
    }
    return moduleID
  }

  private func sourceLocation(for position: AbsolutePosition) -> TCAGraphModel.SourceLocation {
    let loc = converter.location(for: position)
    return TCAGraphModel.SourceLocation(file: filePath, line: loc.line, column: loc.column)
  }

  // MARK: - @Dependency extraction

  private func extractDependency(_ varDecl: VariableDeclSyntax) -> DependencyRef? {
    for attr in varDecl.attributes {
      guard case .attribute(let a) = attr else { continue }
      guard a.attributeName.trimmedDescription == "Dependency" else { continue }
      guard let args = a.arguments?.as(LabeledExprListSyntax.self) else { return nil }
      guard let first = args.first else { return nil }
      if let kp = first.expression.as(KeyPathExprSyntax.self) {
        let keyPath = normalizeKeyPath(kp)
        return DependencyRef(keyPath: keyPath)
      }
      return nil
    }
    return nil
  }

  private func normalizeKeyPath(_ kp: KeyPathExprSyntax) -> String {
    let components = kp.components.map { $0.trimmedDescription }.joined()
    if components.hasPrefix(".") {
      return String(components.dropFirst())
    }
    return components
  }

  // MARK: - State extraction

  private func extractStateStruct(_ decl: StructDeclSyntax) -> StateDecl {
    let protocols = decl.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
    var fields: [StateField] = []
    for member in decl.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
      fields.append(contentsOf: extractStateFields(varDecl))
    }
    return StateDecl(typeName: "State", kind: .struct, protocols: protocols, fields: fields)
  }

  private func extractStateEnum(_ decl: EnumDeclSyntax) -> StateDecl {
    let protocols = decl.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
    var fields: [StateField] = []
    for member in decl.memberBlock.members {
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
      for element in caseDecl.elements {
        let name = element.name.text
        let payload = element.parameterClause?.parameters.map { $0.type.trimmedDescription }.joined(separator: ", ") ?? ""
        let type = payload.isEmpty ? "()" : payload
        fields.append(StateField(name: name, type: type, childRef: extractChildRef(from: type)))
      }
    }
    return StateDecl(typeName: "State", kind: .enum, protocols: protocols, fields: fields)
  }

  private func extractStateFields(_ varDecl: VariableDeclSyntax) -> [StateField] {
    var isPresents = false
    var isShared = false
    var storage: String?

    for attr in varDecl.attributes {
      guard case .attribute(let a) = attr else { continue }
      let name = a.attributeName.trimmedDescription
      switch name {
      case "Presents": isPresents = true
      case "Shared":
        isShared = true
        if let args = a.arguments?.as(LabeledExprListSyntax.self), let first = args.first {
          storage = first.expression.trimmedDescription
        }
      default: break
      }
    }

    var fields: [StateField] = []
    for binding in varDecl.bindings {
      guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
      let typeString = binding.typeAnnotation?.type.trimmedDescription
        ?? inferredTypeFromInitializer(binding.initializer?.value)
        ?? "_"
      let optional = typeString.hasSuffix("?") || typeString.hasPrefix("Optional<")
      let collection = isCollectionType(typeString)
      fields.append(
        StateField(
          name: name,
          type: typeString,
          optional: optional,
          collection: collection,
          presentation: isPresents,
          kind: isShared ? .shared : .regular,
          storage: storage,
          childRef: extractChildRef(from: typeString)
        )
      )
    }
    return fields
  }

  private func inferredTypeFromInitializer(_ expr: ExprSyntax?) -> String? {
    guard let expr else { return nil }
    if let call = expr.as(FunctionCallExprSyntax.self) {
      return call.calledExpression.trimmedDescription
    }
    return nil
  }

  private func isCollectionType(_ type: String) -> Bool {
    return type.hasPrefix("[")
      || type.hasPrefix("Array<")
      || type.hasPrefix("IdentifiedArray")
      || type.hasPrefix("IdentifiedArrayOf<")
      || type.hasPrefix("Set<")
      || type.hasPrefix("Dictionary<")
  }

  private func extractChildRef(from type: String) -> String? {
    var t = type.hasSuffix("?") ? String(type.dropLast()) : type
    if let inner = captureGeneric(t, outer: "IdentifiedArrayOf") { t = inner }
    if let inner = captureGeneric(t, outer: "PresentationState") { t = inner }
    if let inner = captureGeneric(t, outer: "Array") { t = inner }

    if t.hasSuffix(".State") {
      let head = String(t.dropLast(".State".count))
      return head.split(separator: ".").last.map(String.init)
    }
    return nil
  }

  // For `@Reducer enum` payloads like `case foo(LoginViewFeature)` — the payload IS the reducer type.
  private func extractChildRefFromEnumPayload(_ payload: String) -> String? {
    let trimmed = payload.trimmingCharacters(in: .whitespaces)
    return trimmed.split(separator: ".").last.map(String.init)
  }

  private func captureGeneric(_ input: String, outer: String) -> String? {
    guard input.hasPrefix(outer + "<"), input.hasSuffix(">") else { return nil }
    let start = input.index(input.startIndex, offsetBy: outer.count + 1)
    let end = input.index(before: input.endIndex)
    return String(input[start..<end])
  }

  // MARK: - Action extraction

  private func extractAction(_ decl: EnumDeclSyntax) -> ActionDecl {
    let protocols = decl.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
    var cases: [ActionCase] = []
    var nestedEnums: [NestedEnum] = []

    for member in decl.memberBlock.members {
      if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
        for element in caseDecl.elements {
          let name = element.name.text
          let payload = element.parameterClause?.parameters.map { $0.type.trimmedDescription } ?? []
          cases.append(ActionCase(name: name, payload: payload))
        }
      } else if let nested = member.decl.as(EnumDeclSyntax.self) {
        nestedEnums.append(extractNestedActionEnum(nested))
      }
    }
    return ActionDecl(typeName: "Action", protocols: protocols, cases: cases, nestedEnums: nestedEnums)
  }

  private func extractNestedActionEnum(_ decl: EnumDeclSyntax) -> NestedEnum {
    var cases: [ActionCase] = []
    for member in decl.memberBlock.members {
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
      for element in caseDecl.elements {
        let name = element.name.text
        let payload = element.parameterClause?.parameters.map { $0.type.trimmedDescription } ?? []
        cases.append(ActionCase(name: name, payload: payload))
      }
    }
    return NestedEnum(name: decl.name.text, cases: cases)
  }

  // MARK: - Body walking (edges)

  private func walkBody(varDecl: VariableDeclSyntax, sourceName: String, sourceNodeIDGuess: String) {
    // Find the body expression list from the body accessor/getter.
    guard let binding = varDecl.bindings.first else { return }
    guard let accessor = binding.accessorBlock else { return }

    let items: CodeBlockItemListSyntax
    switch accessor.accessors {
    case .accessors(let accessorList):
      // Find a getter; if none, skip.
      guard
        let getter = accessorList.first(where: {
          $0.accessorSpecifier.tokenKind == .keyword(.get)
        }),
        let body = getter.body
      else { return }
      items = body.statements
    case .getter(let stmts):
      items = stmts
    }

    for item in items {
      if let expr = item.item.as(ExprSyntax.self) {
        emitEdges(from: expr, sourceNodeID: sourceNodeIDGuess)
      }
    }
  }

  private func emitEdges(from expr: ExprSyntax, sourceNodeID: String) {
    // A chain like `Reduce{}.ifLet(...).forEach(...)` parses as nested function calls
    // whose callee is a MemberAccessExpr. Unchain by walking to the innermost base.
    if let call = expr.as(FunctionCallExprSyntax.self) {
      if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
        if let base = memberAccess.base {
          emitEdges(from: base, sourceNodeID: sourceNodeID)
        }
        let name = memberAccess.declName.baseName.text
        handleModifier(name: name, call: call, sourceNodeID: sourceNodeID)
        return
      }
      if let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self) {
        let callee = declRef.baseName.text
        handleDirectCall(name: callee, call: call, sourceNodeID: sourceNodeID)
        return
      }
    }
    // Other expression shapes are ignored (bare `DeclReference` like `BindingReducer` alone isn't valid here).
  }

  private func handleDirectCall(name: String, call: FunctionCallExprSyntax, sourceNodeID: String) {
    switch name {
    case "Scope":
      let (statePath, actionPath, childName) = extractScopeArgs(call)
      if let childName {
        rawEdges.append(
          RawEdge(
            sourceNodeID: sourceNodeID,
            filePath: filePath,
            targetName: childName,
            kind: .scope,
            presentation: false,
            statePath: statePath,
            actionPath: actionPath,
            location: sourceLocation(for: call.positionAfterSkippingLeadingTrivia)
          )
        )
      }
    case "BindingReducer", "Reduce", "EmptyReducer", "CombineReducers":
      break
    default:
      break
    }
  }

  private func handleModifier(name: String, call: FunctionCallExprSyntax, sourceNodeID: String) {
    let kind: Edge.Kind
    switch name {
    case "ifLet": kind = .ifLet
    case "ifCaseLet": kind = .ifCaseLet
    case "forEach": kind = .forEach
    default: return
    }

    let (statePath, actionPath, childName) = extractModifierArgs(call)
    let presentation = (statePath ?? "").contains("$")

    if let childName {
      rawEdges.append(
        RawEdge(
          sourceNodeID: sourceNodeID,
          filePath: filePath,
          targetName: childName,
          kind: kind,
          presentation: presentation,
          statePath: statePath,
          actionPath: actionPath,
          location: sourceLocation(for: call.positionAfterSkippingLeadingTrivia)
        )
      )
    }
  }

  /// `Scope(state: \.x, action: \.y) { Child() }` — args always labeled, closure is trailing.
  private func extractScopeArgs(_ call: FunctionCallExprSyntax) -> (state: String?, action: String?, child: String?) {
    var stateKP: String?
    var actionKP: String?
    for arg in call.arguments {
      let label = arg.label?.text
      if label == "state" {
        stateKP = keyPathString(from: arg.expression)
      } else if label == "action" {
        actionKP = keyPathString(from: arg.expression)
      }
    }
    let child = extractTrailingChild(call)
    return (stateKP, actionKP, child)
  }

  /// `.ifLet(\.x, action: \.y) { Child() }` — first arg is typically unlabeled state, then labeled action.
  private func extractModifierArgs(_ call: FunctionCallExprSyntax) -> (state: String?, action: String?, child: String?) {
    var stateKP: String?
    var actionKP: String?
    for (i, arg) in call.arguments.enumerated() {
      let label = arg.label?.text
      if label == nil && i == 0 {
        stateKP = keyPathString(from: arg.expression)
      } else if label == "state" {
        stateKP = keyPathString(from: arg.expression)
      } else if label == "action" {
        actionKP = keyPathString(from: arg.expression)
      }
    }
    let child = extractTrailingChild(call)
    return (stateKP, actionKP, child)
  }

  private func keyPathString(from expr: ExprSyntax) -> String? {
    if let kp = expr.as(KeyPathExprSyntax.self) {
      return kp.trimmedDescription
    }
    return nil
  }

  private func extractTrailingChild(_ call: FunctionCallExprSyntax) -> String? {
    // Check trailing closures first.
    if let closure = call.trailingClosure {
      return firstChildCall(in: closure.statements)
    }
    // Also support closures passed as a regular argument.
    for arg in call.arguments {
      if let closure = arg.expression.as(ClosureExprSyntax.self) {
        if let name = firstChildCall(in: closure.statements) { return name }
      }
    }
    return nil
  }

  private func firstChildCall(in stmts: CodeBlockItemListSyntax) -> String? {
    // Find the first expression statement that's a function call and extract its callee name.
    for item in stmts {
      guard let expr = item.item.as(ExprSyntax.self) else { continue }
      if let call = expr.as(FunctionCallExprSyntax.self) {
        return calleeName(call.calledExpression)
      }
      if let name = expr.trimmedDescription.split(separator: ".").last.map(String.init) {
        // e.g. the closure body is just `Child()` with no args but still a callable
        if !name.isEmpty { return String(name) }
      }
    }
    return nil
  }

  private func calleeName(_ expr: ExprSyntax) -> String? {
    if let declRef = expr.as(DeclReferenceExprSyntax.self) {
      return declRef.baseName.text
    }
    if let member = expr.as(MemberAccessExprSyntax.self) {
      return member.declName.baseName.text
    }
    return expr.trimmedDescription.split(separator: ".").last.map(String.init)
  }
}

// MARK: - Helpers

extension VariableDeclSyntax {
  fileprivate var isBodyProperty: Bool {
    for binding in bindings {
      if binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body" {
        return true
      }
    }
    return false
  }
}
