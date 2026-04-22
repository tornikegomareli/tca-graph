import type { EdgeKind, Graph } from "../types";
import { moduleStyle } from "../layout";

interface Props {
  graph: Graph;
  selectedModules: Set<string>;
  selectedKinds: Set<EdgeKind>;
  onModulesChange: (next: Set<string>) => void;
  onKindsChange: (next: Set<EdgeKind>) => void;
  stats: { nodes: number; edges: number; orphans: number };
}

const KINDS: EdgeKind[] = ["scope", "ifLet", "ifCaseLet", "forEach", "combine"];

export function Sidebar({
  graph,
  selectedModules,
  selectedKinds,
  onModulesChange,
  onKindsChange,
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
  const selectAllModules = () => onModulesChange(new Set(modulesWithNodes.map((m) => m.id)));
  const clearModules = () => onModulesChange(new Set());

  return (
    <aside className="sidebar">
      <div className="sb-header">
        <h1>tca-graph</h1>
        <div className="sb-sub">
          {stats.nodes} nodes · {stats.edges} edges · {stats.orphans} orphans
        </div>
        <div className="sb-source" title={graph.source.rootPath}>
          {graph.source.rootPath.split("/").slice(-2).join("/")}
          {graph.source.gitCommit && <span className="sb-commit"> @{graph.source.gitCommit}</span>}
        </div>
      </div>

      <section className="sb-section">
        <div className="sb-section-header">
          <h2>Edge kinds</h2>
        </div>
        <div className="sb-chips">
          {KINDS.map((k) => (
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
