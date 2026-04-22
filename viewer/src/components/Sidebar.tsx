import type { EdgeKind, Graph, SharedStorageKind } from "../types";
import { moduleStyle, storageKindStyle } from "../layout";

export type ViewMode = "reducers" | "shared";

interface Props {
  graph: Graph;
  mode: ViewMode;

  selectedModules: Set<string>;
  onModulesChange: (next: Set<string>) => void;

  // Reducer-mode filters
  selectedKinds: Set<EdgeKind>;
  onKindsChange: (next: Set<EdgeKind>) => void;

  // Shared-mode filters
  selectedStorageKinds: Set<SharedStorageKind>;
  onStorageKindsChange: (next: Set<SharedStorageKind>) => void;
  keyQuery: string;
  onKeyQueryChange: (q: string) => void;
  hideSingleReference: boolean;
  onHideSingleReferenceChange: (v: boolean) => void;

  stats: { nodes: number; edges: number; orphans: number };
}

const EDGE_KINDS: EdgeKind[] = ["scope", "ifLet", "ifCaseLet", "forEach", "combine"];
const STORAGE_KINDS: SharedStorageKind[] = ["appStorage", "inMemory", "fileStorage", "other"];

export function Sidebar({
  graph,
  mode,
  selectedModules,
  onModulesChange,
  selectedKinds,
  onKindsChange,
  selectedStorageKinds,
  onStorageKindsChange,
  keyQuery,
  onKeyQueryChange,
  hideSingleReference,
  onHideSingleReferenceChange,
  stats,
}: Props) {
  const moduleNodeCount = new Map<string, number>();
  for (const n of graph.nodes) {
    moduleNodeCount.set(n.moduleId, (moduleNodeCount.get(n.moduleId) ?? 0) + 1);
  }
  const modulesWithNodes = graph.modules
    .filter((m) => (moduleNodeCount.get(m.id) ?? 0) > 0)
    .sort((a, b) => a.name.localeCompare(b.name));

  const toggleModule = (id: string) => {
    const next = new Set(selectedModules);
    if (next.has(id)) next.delete(id); else next.add(id);
    onModulesChange(next);
  };
  const toggleKind = (k: EdgeKind) => {
    const next = new Set(selectedKinds);
    if (next.has(k)) next.delete(k); else next.add(k);
    onKindsChange(next);
  };
  const toggleStorageKind = (k: SharedStorageKind) => {
    const next = new Set(selectedStorageKinds);
    if (next.has(k)) next.delete(k); else next.add(k);
    onStorageKindsChange(next);
  };

  const selectAllModules = () => onModulesChange(new Set(modulesWithNodes.map((m) => m.id)));
  const clearModules = () => onModulesChange(new Set());

  return (
    <aside className="sidebar">
      <div className="sb-header">
        <h1>tca-graph</h1>
        <div className="sb-sub">
          {stats.nodes} nodes · {stats.edges} edges
          {mode === "reducers" && ` · ${stats.orphans} orphans`}
        </div>
        <div className="sb-source" title={graph.source.rootPath}>
          {graph.source.rootPath.split("/").slice(-2).join("/")}
          {graph.source.gitCommit && <span className="sb-commit"> @{graph.source.gitCommit}</span>}
        </div>
      </div>

      {mode === "reducers" && (
        <section className="sb-section">
          <div className="sb-section-header">
            <h2>Edge kinds</h2>
          </div>
          <div className="sb-chips">
            {EDGE_KINDS.map((k) => (
              <button
                key={k}
                className={`sb-chip sb-kind-${k} ${selectedKinds.has(k) ? "is-on" : ""}`}
                onClick={() => toggleKind(k)}
              >
                {k}
              </button>
            ))}
          </div>
        </section>
      )}

      {mode === "shared" && (
        <>
          <section className="sb-section">
            <div className="sb-section-header">
              <h2>Storage kinds</h2>
            </div>
            <div className="sb-chips">
              {STORAGE_KINDS.map((k) => {
                const style = storageKindStyle[k];
                const on = selectedStorageKinds.has(k);
                return (
                  <button
                    key={k}
                    className={`sb-chip ${on ? "is-on" : ""}`}
                    onClick={() => toggleStorageKind(k)}
                    style={on ? { background: style.bg, color: style.fg, borderColor: style.fg } : undefined}
                  >
                    {k}
                  </button>
                );
              })}
            </div>
          </section>

          <section className="sb-section">
            <div className="sb-section-header">
              <h2>Key filter</h2>
            </div>
            <input
              type="text"
              className="sb-input"
              placeholder="Substring match…"
              value={keyQuery}
              onChange={(e) => onKeyQueryChange(e.target.value)}
            />
            <label className="sb-checkbox">
              <input
                type="checkbox"
                checked={hideSingleReference}
                onChange={(e) => onHideSingleReferenceChange(e.target.checked)}
              />
              <span>Hide single-reference storages</span>
            </label>
          </section>
        </>
      )}

      <section className="sb-section">
        <div className="sb-section-header">
          <h2>Modules ({modulesWithNodes.length})</h2>
          <div className="sb-actions">
            <button onClick={selectAllModules}>all</button>
            <button onClick={clearModules}>none</button>
          </div>
        </div>
        <ul className="sb-modules">
          {modulesWithNodes.map((m) => {
            const ms = moduleStyle(m.id);
            return (
              <li key={m.id}>
                <label>
                  <input
                    type="checkbox"
                    checked={selectedModules.has(m.id)}
                    onChange={() => toggleModule(m.id)}
                  />
                  <span className="sb-mod-swatch" style={{ background: ms.fg }} />
                  <span className="sb-mod-name">{m.name}</span>
                  <span className="sb-mod-count">{moduleNodeCount.get(m.id) ?? 0}</span>
                </label>
              </li>
            );
          })}
        </ul>
      </section>
    </aside>
  );
}
