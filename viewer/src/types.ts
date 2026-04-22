export type ModuleKind = "spmTarget" | "folder" | "xcodeTarget";

export interface Module {
  id: string;
  name: string;
  kind: ModuleKind;
  path: string;
  packageManifest?: string | null;
}

export type StateFieldKind = "regular" | "shared";

export interface StateField {
  name: string;
  type: string;
  optional: boolean;
  collection: boolean;
  presentation: boolean;
  kind: StateFieldKind;
  storage?: string | null;
  childRef?: string | null;
}

export interface ActionCase {
  name: string;
  payload: string[];
}

export interface NestedEnum {
  name: string;
  cases: ActionCase[];
}

export interface StateDecl {
  typeName: string;
  kind: "struct" | "enum";
  protocols: string[];
  fields: StateField[];
}

export interface ActionDecl {
  typeName: string;
  protocols: string[];
  cases: ActionCase[];
  nestedEnums: NestedEnum[];
}

export interface DependencyRef {
  keyPath: string;
  typeName?: string | null;
}

export type Dialect = "macro" | "protocol" | "legacy" | "unknown";

export interface NodeData {
  id: string;
  name: string;
  kind: "reducer";
  moduleId: string;
  location: { file: string; line: number; column: number };
  tcaDialect: Dialect;
  attributes: string[];
  usesBinding: boolean;
  state?: StateDecl | null;
  action?: ActionDecl | null;
  dependencies: DependencyRef[];
}

export type EdgeKind = "scope" | "ifLet" | "ifCaseLet" | "forEach" | "combine";

export interface EdgeData {
  id: string;
  sourceId: string;
  targetId: string;
  kind: EdgeKind;
  presentation: boolean;
  statePath?: string | null;
  actionPath?: string | null;
  location?: { file: string; line: number; column: number } | null;
}

export interface Diagnostic {
  kind: "parseError" | "unresolvedChild" | "ambiguousReference" | "unknownBodyElement";
  message: string;
  location?: { file: string; line: number; column: number } | null;
}

export type SharedStorageKind = "appStorage" | "inMemory" | "fileStorage" | "other";

export interface SharedStorageReference {
  nodeId: string;
  fieldName: string;
}

export interface SharedStorage {
  id: string;
  kind: SharedStorageKind;
  key: string;
  rawDescriptor: string;
  referencedBy: SharedStorageReference[];
}

export interface Graph {
  schemaVersion: string;
  generator: { name: string; version: string };
  generatedAt: string;
  source: {
    rootPath: string;
    gitCommit?: string | null;
    tca: { detectedVersion?: string | null; dialect: Dialect };
  };
  modules: Module[];
  nodes: NodeData[];
  edges: EdgeData[];
  sharedStorages?: SharedStorage[];
  diagnostics: Diagnostic[];
}
