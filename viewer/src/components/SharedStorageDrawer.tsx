import { useMemo } from "react";
import type { Graph, SharedStorage } from "../types";
import { moduleStyle, storageKindStyle } from "../layout";

interface Props {
  graph: Graph;
  storage: SharedStorage;
  /// Nodes currently visible under the reducer-view module filter. References whose
  /// target isn't in this set are marked "(hidden by filter)" — clicking still works
  /// because focusNode auto-restores the hidden module.
  reducerVisibleNodeIds: Set<string>;
  onClose: () => void;
  onNavigateToReducer: (nodeId: string) => void;
}

export function SharedStorageDrawer({
  graph,
  storage,
  reducerVisibleNodeIds,
  onClose,
  onNavigateToReducer,
}: Props) {
  const nodeById = useMemo(() => new Map(graph.nodes.map((n) => [n.id, n])), [graph.nodes]);
  const moduleById = useMemo(() => new Map(graph.modules.map((m) => [m.id, m])), [graph.modules]);
  const kind = storageKindStyle[storage.kind];

  return (
    <aside className="drawer">
      <header className="dr-header">
        <div className="dr-titles">
          <span
            className="ssd-kind"
            style={{ color: kind.fg, background: kind.bg }}
            title={storage.kind}
          >
            {kind.label}
          </span>
          <h2 className="ssd-key">{storage.key}</h2>
          <div className="dr-sub">
            <span className="dr-muted">{storage.kind}</span>
            <span className="dr-muted">· {storage.referencedBy.length} references</span>
          </div>
        </div>
        <button className="dr-close" onClick={onClose} aria-label="Close">×</button>
      </header>

      <div className="dr-body">
        <div className="dr-subheader">Descriptor</div>
        <pre className="ssd-descriptor">{storage.rawDescriptor}</pre>

        <div className="dr-subheader" style={{ marginTop: 16 }}>
          Referenced by ({storage.referencedBy.length})
        </div>
        <ul className="dr-edges">
          {storage.referencedBy.map((ref, i) => {
            const node = nodeById.get(ref.nodeId);
            const moduleName = node ? moduleById.get(node.moduleId)?.name ?? node.moduleId : "?";
            const ms = node ? moduleStyle(node.moduleId) : null;
            const hiddenByFilter = Boolean(node) && !reducerVisibleNodeIds.has(ref.nodeId);
            return (
              <li key={`${ref.nodeId}-${ref.fieldName}-${i}`}>
                {ms && (
                  <span
                    className="dr-module"
                    style={{ color: ms.fg, background: ms.bg, borderColor: ms.border }}
                  >
                    {moduleName}
                  </span>
                )}
                <button
                  className="dr-edge-target"
                  onClick={() => onNavigateToReducer(ref.nodeId)}
                  disabled={!node}
                  title={hiddenByFilter
                    ? "Module is hidden by filter — clicking will restore it and jump"
                    : "Jump to this reducer in the main graph"}
                >
                  {node?.name ?? "(unresolved)"}
                </button>
                <code className="dr-edge-path">.{ref.fieldName}</code>
                {hiddenByFilter && <span className="ssd-hidden-hint">hidden</span>}
              </li>
            );
          })}
        </ul>
      </div>
    </aside>
  );
}
