import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Background,
  Controls,
  MiniMap,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
  type Node as RFNode,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import { Sidebar } from "./components/Sidebar";
import { ReducerNode } from "./components/ReducerNode";
import { DetailsDrawer } from "./components/DetailsDrawer";
import { SearchOverlay } from "./components/SearchOverlay";
import { applyViewState, layoutGraph } from "./layout";
import { buildNeighborhood } from "./graph";
import type { EdgeKind, Graph } from "./types";

const nodeTypes = { reducer: ReducerNode };

export default function App() {
  const [graph, setGraph] = useState<Graph | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/graph.json")
      .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json(); })
      .then((g: Graph) => setGraph(g))
      .catch((e) => setError(String(e)));
  }, []);

  if (error) {
    return (
      <div className="empty">
        <h2>Failed to load graph.json</h2>
        <pre>{error}</pre>
        <p>Generate one with <code>tca-graph analyze &lt;path&gt; -o viewer/public/graph.json</code></p>
      </div>
    );
  }
  if (!graph) return <div className="empty">Loading…</div>;

  return (
    <ReactFlowProvider>
      <GraphView graph={graph} />
    </ReactFlowProvider>
  );
}

function GraphView({ graph }: { graph: Graph }) {
  const rf = useReactFlow();

  const [selectedModules, setSelectedModules] = useState<Set<string>>(
    () => new Set(graph.nodes.map((n) => n.moduleId))
  );
  const [selectedKinds, setSelectedKinds] = useState<Set<EdgeKind>>(
    () => new Set(["scope", "ifLet", "ifCaseLet", "forEach", "combine"])
  );
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [searchOpen, setSearchOpen] = useState(false);

  const moduleNameById = useMemo(
    () => new Map(graph.modules.map((m) => [m.id, m.name])),
    [graph.modules]
  );
  const nodeById = useMemo(
    () => new Map(graph.nodes.map((n) => [n.id, n])),
    [graph.nodes]
  );

  // Pass 1: dagre runs only when graph or structural filters change.
  const baseLaid = useMemo(
    () => layoutGraph(graph, { modules: selectedModules, edgeKinds: selectedKinds }),
    [graph, selectedModules, selectedKinds]
  );

  // Pass 2: hover/selection only flips classNames; positions unchanged.
  // Focus is computed against the *filtered* edges so it matches the visible topology —
  // a node whose only connection is a hidden edge won't be highlighted.
  const focusIds = useMemo(() => {
    const activeId = hoveredId ?? selectedId;
    if (!activeId) return null;
    const visibleIds = new Set(baseLaid.filtered.nodes.map((n) => n.id));
    if (!visibleIds.has(activeId)) return null;
    return buildNeighborhood(baseLaid.filtered.edges, activeId).all;
  }, [baseLaid.filtered, hoveredId, selectedId]);

  const laid = useMemo(
    () => applyViewState(baseLaid, { focusIds, selectedId }),
    [baseLaid, focusIds, selectedId]
  );

  // Global keyboard shortcuts
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const isTyping = (e.target as HTMLElement | null)?.tagName === "INPUT"
                    || (e.target as HTMLElement | null)?.tagName === "TEXTAREA";
      if (e.key === "Escape") {
        if (searchOpen) setSearchOpen(false);
        else if (selectedId) setSelectedId(null);
        return;
      }
      if (isTyping) return;
      if ((e.key === "k" && (e.metaKey || e.ctrlKey)) || e.key === "/") {
        e.preventDefault();
        setSearchOpen(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [searchOpen, selectedId]);

  const focusNode = useCallback(
    (id: string) => {
      setSelectedId(id);
      setSearchOpen(false);
      // Center the viewport on the node
      const rfNode = rf.getNode(id);
      if (rfNode) {
        rf.setCenter(rfNode.position.x + 140, rfNode.position.y + 100, { zoom: 1.1, duration: 400 });
      }
    },
    [rf]
  );

  const selectedNode = selectedId ? nodeById.get(selectedId) ?? null : null;

  const onNodeClick = useCallback((_: unknown, n: RFNode) => focusNode(n.id), [focusNode]);

  // Hover is gated to avoid flicker during rapid mouse drive-bys.
  //   - First activation needs a dwell period (user actually rested on this node).
  //   - Once activated, switching between nodes is near-instant (feels snappy).
  //   - Leaving also has a small grace window so flicking between adjacent nodes
  //     doesn't cause a full unfade/refade cycle.
  const hoverTimerRef = useRef<number | null>(null);
  const hoverTargetRef = useRef<string | null>(null);

  const scheduleHover = useCallback((delay: number) => {
    if (hoverTimerRef.current !== null) window.clearTimeout(hoverTimerRef.current);
    hoverTimerRef.current = window.setTimeout(() => {
      hoverTimerRef.current = null;
      setHoveredId(hoverTargetRef.current);
    }, delay);
  }, []);

  const onNodeMouseEnter = useCallback(
    (_: unknown, n: RFNode) => {
      hoverTargetRef.current = n.id;
      // First activation: wait for deliberate dwell. Already active: quick switch.
      const delay = hoveredId === null ? 250 : 60;
      scheduleHover(delay);
    },
    [hoveredId, scheduleHover]
  );

  const onNodeMouseLeave = useCallback(() => {
    hoverTargetRef.current = null;
    scheduleHover(120);
  }, [scheduleHover]);

  const onPaneClick = useCallback(() => { setSelectedId(null); }, []);

  // Clean up any pending timer on unmount.
  useEffect(() => {
    return () => {
      if (hoverTimerRef.current !== null) window.clearTimeout(hoverTimerRef.current);
    };
  }, []);

  return (
    <div className={`layout ${selectedNode ? "with-drawer" : ""}`}>
      <Sidebar
        graph={graph}
        selectedModules={selectedModules}
        selectedKinds={selectedKinds}
        onModulesChange={setSelectedModules}
        onKindsChange={setSelectedKinds}
        stats={{ nodes: laid.nodes.length, edges: laid.edges.length, orphans: laid.orphans.length }}
      />
      <main className="canvas">
        <ReactFlow
          nodes={laid.nodes}
          edges={laid.edges}
          nodeTypes={nodeTypes}
          fitView
          proOptions={{ hideAttribution: true }}
          minZoom={0.1}
          maxZoom={2}
          onNodeClick={onNodeClick}
          onNodeMouseEnter={onNodeMouseEnter}
          onNodeMouseLeave={onNodeMouseLeave}
          onPaneClick={onPaneClick}
        >
          <Background gap={24} size={1} color="#2a2e35" />
          <Controls />
          <MiniMap pannable zoomable nodeColor="#5b8def" />
        </ReactFlow>

        <button className="search-pill" onClick={() => setSearchOpen(true)} title="Search (⌘K or /)">
          <span>Search</span>
          <kbd>⌘K</kbd>
        </button>
      </main>

      {selectedNode && (
        <DetailsDrawer
          graph={graph}
          filteredEdges={baseLaid.filtered.edges}
          node={selectedNode}
          onClose={() => setSelectedId(null)}
          onNavigateTo={focusNode}
        />
      )}

      {searchOpen && (
        <SearchOverlay
          nodes={graph.nodes}
          moduleNameById={moduleNameById}
          onSelect={focusNode}
          onClose={() => setSearchOpen(false)}
        />
      )}
    </div>
  );
}
