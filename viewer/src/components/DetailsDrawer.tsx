import { useMemo, useState } from "react";
import type { EdgeData, Graph, NodeData } from "../types";
import { moduleStyle } from "../layout";
import { buildNeighborhood } from "../graph";

interface Props {
  graph: Graph;
  filteredEdges: EdgeData[];
  node: NodeData;
  onClose: () => void;
  onNavigateTo: (nodeId: string) => void;
}

export function DetailsDrawer({ graph, filteredEdges, node, onClose, onNavigateTo }: Props) {
  // Use filtered edges so the Parents / Children lists reflect only visible connections.
  const neighborhood = useMemo(() => buildNeighborhood(filteredEdges, node.id), [filteredEdges, node.id]);
  const nodeById = useMemo(() => new Map(graph.nodes.map((n) => [n.id, n])), [graph.nodes]);
  const moduleById = useMemo(() => new Map(graph.modules.map((m) => [m.id, m])), [graph.modules]);
  const mod = moduleStyle(node.moduleId);
  const moduleName = moduleById.get(node.moduleId)?.name ?? node.moduleId;

  const [tab, setTab] = useState<"state" | "actions" | "deps" | "complexity" | "edges">("state");

  return (
    <aside className="drawer">
      <header className="dr-header">
        <div className="dr-titles">
          <span
            className="dr-module"
            style={{ color: mod.fg, background: mod.bg, borderColor: mod.border }}
          >
            {moduleName}
          </span>
          <h2>{node.name}</h2>
          <div className="dr-sub">
            <span className="dr-dialect">{node.tcaDialect}</span>
            {node.usesBinding && <span className="dr-chip dr-chip-binding">binding</span>}
            {node.attributes.map((a) => (
              <span key={a} className="dr-chip dr-chip-attr">{a}</span>
            ))}
          </div>
        </div>
        <button className="dr-close" onClick={onClose} aria-label="Close">×</button>
      </header>

      <OpenInEditor file={node.location.file} line={node.location.line} />

      <nav className="dr-tabs">
        <TabButton active={tab === "state"} onClick={() => setTab("state")}>
          State <span className="dr-tab-count">{node.state?.fields.length ?? 0}</span>
        </TabButton>
        <TabButton active={tab === "actions"} onClick={() => setTab("actions")}>
          Actions <span className="dr-tab-count">{(node.action?.cases.length ?? 0) + nestedCount(node)}</span>
        </TabButton>
        <TabButton active={tab === "deps"} onClick={() => setTab("deps")}>
          Deps <span className="dr-tab-count">{node.dependencies.length}</span>
        </TabButton>
        <TabButton active={tab === "complexity"} onClick={() => setTab("complexity")}>
          Complexity <span className="dr-tab-count">{node.complexityScore ?? 0}</span>
        </TabButton>
        <TabButton active={tab === "edges"} onClick={() => setTab("edges")}>
          Graph <span className="dr-tab-count">{neighborhood.incomingEdges.length + neighborhood.outgoingEdges.length}</span>
        </TabButton>
      </nav>

      <div className="dr-body">
        {tab === "state" && <StateTab node={node} />}
        {tab === "actions" && <ActionsTab node={node} />}
        {tab === "deps" && <DepsTab node={node} />}
        {tab === "complexity" && (
          <ComplexityTab
            node={node}
            // Use unfiltered graph.edges so the Children breakdown stays consistent
            // with the parser-computed complexityScore (which sees all edges) even
            // when the user toggles edge-kind filters in the sidebar.
            outgoingCount={graph.edges.filter((e) => e.sourceId === node.id).length}
          />
        )}
        {tab === "edges" && (
          <EdgesTab
            node={node}
            incoming={neighborhood.incomingEdges}
            outgoing={neighborhood.outgoingEdges}
            nodeById={nodeById}
            onNavigateTo={onNavigateTo}
          />
        )}
      </div>
    </aside>
  );
}

function TabButton({
  active, onClick, children,
}: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button className={`dr-tab ${active ? "is-active" : ""}`} onClick={onClick}>{children}</button>
  );
}

function nestedCount(n: NodeData) {
  return (n.action?.nestedEnums ?? []).reduce((acc, e) => acc + e.cases.length, 0);
}

function OpenInEditor({ file, line }: { file: string; line: number }) {
  const [copied, setCopied] = useState(false);

  const copyPath = async () => {
    await navigator.clipboard.writeText(`${file}:${line}`);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  const relative = file.split("/").slice(-3).join("/");
  const cursor = `cursor://file/${file}:${line}`;
  const vscode = `vscode://file/${file}:${line}`;
  const zed    = `zed://file/${file}:${line}`;

  return (
    <div className="dr-openin">
      <code className="dr-path" title={file}>{relative}:{line}</code>
      <div className="dr-openin-actions">
        <a className="dr-btn" href={cursor} title="Open in Cursor">Cursor</a>
        <a className="dr-btn" href={vscode} title="Open in VS Code">VS Code</a>
        <a className="dr-btn" href={zed}    title="Open in Zed">Zed</a>
        <button className="dr-btn" onClick={copyPath} title="Copy file:line">
          {copied ? "Copied" : "Copy path"}
        </button>
      </div>
    </div>
  );
}

// ------------------------------------------------------------------
// State tab
// ------------------------------------------------------------------

function StateTab({ node }: { node: NodeData }) {
  if (!node.state) return <div className="dr-empty">No state extracted.</div>;

  return (
    <div>
      <div className="dr-subheader">
        <code>{node.state.typeName}</code>
        <span className="dr-muted">· {node.state.kind}</span>
        {node.state.protocols.length > 0 && (
          <span className="dr-muted"> : {node.state.protocols.join(", ")}</span>
        )}
      </div>
      <table className="dr-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Type</th>
            <th>Flags</th>
          </tr>
        </thead>
        <tbody>
          {node.state.fields.map((f) => (
            <tr key={f.name}>
              <td><code>{f.name}</code></td>
              <td><code className="dr-type">{f.type}</code></td>
              <td>
                {f.optional     && <span className="dr-chip dr-chip-dim">opt</span>}
                {f.collection   && <span className="dr-chip dr-chip-dim">[]</span>}
                {f.presentation && <span className="dr-chip dr-chip-pres">@Presents</span>}
                {f.kind === "shared" && (
                  <span className="dr-chip dr-chip-shared" title={f.storage ?? undefined}>@Shared</span>
                )}
                {f.childRef && <span className="dr-chip dr-chip-child">→{f.childRef}</span>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ------------------------------------------------------------------
// Actions tab
// ------------------------------------------------------------------

function ActionsTab({ node }: { node: NodeData }) {
  if (!node.action) return <div className="dr-empty">No action extracted.</div>;

  return (
    <div>
      <div className="dr-subheader">
        <code>{node.action.typeName}</code>
        {node.action.protocols.length > 0 && (
          <span className="dr-muted"> : {node.action.protocols.join(", ")}</span>
        )}
      </div>
      <ul className="dr-list">
        {node.action.cases.map((c) => (
          <li key={c.name}>
            <code>.{c.name}</code>
            {c.payload.length > 0 && (
              <span className="dr-payload">({c.payload.join(", ")})</span>
            )}
          </li>
        ))}
      </ul>

      {node.action.nestedEnums.map((ne) => (
        <div key={ne.name} className="dr-nested">
          <div className="dr-subheader">
            <code>{ne.name}</code>
            <span className="dr-muted">· {ne.cases.length} cases</span>
          </div>
          <ul className="dr-list">
            {ne.cases.map((c) => (
              <li key={c.name}>
                <code>.{c.name}</code>
                {c.payload.length > 0 && (
                  <span className="dr-payload">({c.payload.join(", ")})</span>
                )}
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

// ------------------------------------------------------------------
// Dependencies tab
// ------------------------------------------------------------------

function DepsTab({ node }: { node: NodeData }) {
  if (node.dependencies.length === 0) return <div className="dr-empty">No dependencies.</div>;
  return (
    <ul className="dr-list">
      {node.dependencies.map((d) => (
        <li key={d.keyPath}>
          <code>\.{d.keyPath}</code>
          {d.typeName && <span className="dr-muted"> : {d.typeName}</span>}
        </li>
      ))}
    </ul>
  );
}

// ------------------------------------------------------------------
// Complexity tab (score breakdown + risks)
// ------------------------------------------------------------------

function ComplexityTab({
  node, outgoingCount,
}: { node: NodeData; outgoingCount: number }) {
  const score = node.complexityScore ?? 0;
  const fields = node.state?.fields.length ?? 0;
  const actionCases = node.action?.cases.length ?? 0;
  const nestedActionCases = (node.action?.nestedEnums ?? []).reduce(
    (acc, e) => acc + e.cases.length,
    0
  );
  const chainDepth = node.chainDepthMax ?? 0;
  const risks = node.risks ?? [];

  return (
    <div>
      <div className="dr-score">
        <div className="dr-score-value">{score}</div>
        <div className="dr-score-label">complexity score</div>
      </div>

      <div className="dr-subheader" style={{ marginTop: 16 }}>Breakdown</div>
      <ul className="dr-list">
        <li><span>Fields</span><span className="dr-muted dr-num">{fields}</span></li>
        <li><span>Actions</span><span className="dr-muted dr-num">{actionCases}</span></li>
        {nestedActionCases > 0 && (
          <li><span>Nested action cases</span><span className="dr-muted dr-num">{nestedActionCases}</span></li>
        )}
        <li><span>Children</span><span className="dr-muted dr-num">{outgoingCount}</span></li>
        <li><span>Max modifier-chain depth</span><span className="dr-muted dr-num">{chainDepth}</span></li>
      </ul>

      <div className="dr-subheader" style={{ marginTop: 16 }}>
        Risks {risks.length > 0 && <span className="dr-muted">({risks.length})</span>}
      </div>
      {risks.length === 0 ? (
        <div className="dr-empty">No compile-time risks detected.</div>
      ) : (
        <ul className="dr-list">
          {risks.map((r) => (
            <li key={r.kind} className="dr-risk-row">
              <div>
                <div className="dr-risk-msg">{r.message}</div>
                <div className="dr-muted dr-risk-meta">
                  {r.kind} · {r.value}/{r.threshold}
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

// ------------------------------------------------------------------
// Edges tab (parents + children)
// ------------------------------------------------------------------

function EdgesTab({
  node, incoming, outgoing, nodeById, onNavigateTo,
}: {
  node: NodeData;
  incoming: EdgeData[];
  outgoing: EdgeData[];
  nodeById: Map<string, NodeData>;
  onNavigateTo: (id: string) => void;
}) {
  return (
    <div>
      <div className="dr-subheader">Parents ({incoming.length})</div>
      {incoming.length === 0 ? (
        <div className="dr-empty">No parents. {node.name} is a root.</div>
      ) : (
        <EdgeList edges={incoming} endpointId={(e) => e.sourceId} nodeById={nodeById} onNavigateTo={onNavigateTo} direction="incoming" />
      )}

      <div className="dr-subheader" style={{ marginTop: 16 }}>Children ({outgoing.length})</div>
      {outgoing.length === 0 ? (
        <div className="dr-empty">No children.</div>
      ) : (
        <EdgeList edges={outgoing} endpointId={(e) => e.targetId} nodeById={nodeById} onNavigateTo={onNavigateTo} direction="outgoing" />
      )}
    </div>
  );
}

function EdgeList({
  edges, endpointId, nodeById, onNavigateTo, direction,
}: {
  edges: EdgeData[];
  endpointId: (e: EdgeData) => string;
  nodeById: Map<string, NodeData>;
  onNavigateTo: (id: string) => void;
  direction: "incoming" | "outgoing";
}) {
  return (
    <ul className="dr-edges">
      {edges.map((e) => {
        const otherId = endpointId(e);
        const other = nodeById.get(otherId);
        const otherName = other?.name ?? otherId.replace("node:unresolved.", "?");
        const clickable = Boolean(other);
        return (
          <li key={e.id}>
            <span className={`dr-edge-kind dr-edge-${e.kind}`}>{e.kind}</span>
            {e.presentation && <span className="dr-chip dr-chip-pres">presents</span>}
            <span className="dr-edge-arrow">{direction === "incoming" ? "←" : "→"}</span>
            <button
              className={`dr-edge-target ${clickable ? "" : "is-disabled"}`}
              onClick={() => clickable && onNavigateTo(otherId)}
              disabled={!clickable}
            >
              {otherName}
            </button>
            {e.statePath && <code className="dr-edge-path">{e.statePath}</code>}
          </li>
        );
      })}
    </ul>
  );
}
