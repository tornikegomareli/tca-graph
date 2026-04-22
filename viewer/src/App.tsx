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

import { Sidebar, type ViewMode } from "./components/Sidebar";
import { ReducerNode } from "./components/ReducerNode";
import { SharedStorageNode } from "./components/SharedStorageNode";
import { DetailsDrawer } from "./components/DetailsDrawer";
import { SharedStorageDrawer } from "./components/SharedStorageDrawer";
import { SearchOverlay } from "./components/SearchOverlay";
import { applyViewState, layoutGraph, layoutSharedGraph } from "./layout";
import { buildNeighborhood } from "./graph";
import type { EdgeKind, Graph, SharedStorage, SharedStorageKind } from "./types";

const nodeTypes = { reducer: ReducerNode, sharedStorage: SharedStorageNode };

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

  const [mode, setMode] = useState<ViewMode>("reducers");
  const [selectedModules, setSelectedModules] = useState<Set<string>>(
    () => new Set(graph.nodes.map((n) => n.moduleId))
  );
  const [selectedKinds, setSelectedKinds] = useState<Set<EdgeKind>>(
    () => new Set(["scope", "ifLet", "ifCaseLet", "forEach", "combine"])
  );
  const [selectedStorageKinds, setSelectedStorageKinds] = useState<Set<SharedStorageKind>>(
    () => new Set(["appStorage", "inMemory", "fileStorage", "other"])
  );
  const [keyQuery, setKeyQuery] = useState("");
  const [hideSingleReference, setHideSingleReference] = useState(false);

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
  const storageById = useMemo(
    () => new Map((graph.sharedStorages ?? []).map((s) => [s.id, s])),
    [graph.sharedStorages]
  );

  // Pass 1: dagre runs only when graph or structural filters change.
  const baseLaid = useMemo(
    () => {
      if (mode === "shared") {
        return layoutSharedGraph(graph, {
          modules: selectedModules,
          storageKinds: selectedStorageKinds,
          keyQuery,
          hideSingleReference,
        });
      }
      return layoutGraph(graph, { modules: selectedModules, edgeKinds: selectedKinds });
    },
    [graph, mode, selectedModules, selectedKinds, selectedStorageKinds, keyQuery, hideSingleReference]
  );

  // Pass 2: hover/selection only flips classNames; positions unchanged.
  const focusIds = useMemo(() => {
    const activeId = hoveredId ?? selectedId;
    if (!activeId) return null;
    const visibleIds = new Set(baseLaid.nodes.map((n) => n.id));
    if (!visibleIds.has(activeId)) return null;
    return buildNeighborhood(baseLaid.filtered.edges, activeId).all;
  }, [baseLaid, hoveredId, selectedId]);

  const laid = useMemo(
    () => applyViewState(baseLaid, { focusIds, selectedId }),
    [baseLaid, focusIds, selectedId]
  );

  // Manual mode toggle: clear selection so a stale id from the other view doesn't linger.
  // Importantly, this runs only on user-initiated toggle, NOT as a side-effect of mode
  // changes — otherwise `focusNode` (which flips mode to navigate from the shared drawer
  // to a reducer) would race with the reset and land with nothing selected.
  const toggleMode = useCallback((next: ViewMode) => {
    if (next === mode) return;
    setMode(next);
    setSelectedId(null);
    setHoveredId(null);
  }, [mode]);

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
      // If the caller is navigating to a reducer while we're on the shared view,
      // flip back so the node actually exists in the laid graph before we center.
      const isStorage = id.startsWith("shared:");
      if (!isStorage && mode === "shared") {
        setMode("reducers");
      }
      setSelectedId(id);
      setSearchOpen(false);
      // Center viewport — defer to next frame so the layout after mode flip is in place.
      requestAnimationFrame(() => {
        const rfNode = rf.getNode(id);
        if (rfNode) {
          rf.setCenter(rfNode.position.x + 140, rfNode.position.y + 60, { zoom: 1.1, duration: 400 });
        }
      });
    },
    [mode, rf]
  );

  const selectedNode = selectedId && !selectedId.startsWith("shared:")
    ? nodeById.get(selectedId) ?? null
    : null;
  const selectedStorage: SharedStorage | null = selectedId?.startsWith("shared:")
    ? storageById.get(selectedId) ?? null
    : null;
  const drawerOpen = selectedNode !== null || selectedStorage !== null;

  const onNodeClick = useCallback((_: unknown, n: RFNode) => focusNode(n.id), [focusNode]);

  // Hover is gated to avoid flicker during rapid mouse drive-bys.
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

  useEffect(() => {
    return () => {
      if (hoverTimerRef.current !== null) window.clearTimeout(hoverTimerRef.current);
    };
  }, []);

  return (
    <div className={`layout ${drawerOpen ? "with-drawer" : ""}`}>
      <Sidebar
        graph={graph}
        mode={mode}
        selectedModules={selectedModules}
        onModulesChange={setSelectedModules}
        selectedKinds={selectedKinds}
        onKindsChange={setSelectedKinds}
        selectedStorageKinds={selectedStorageKinds}
        onStorageKindsChange={setSelectedStorageKinds}
        keyQuery={keyQuery}
        onKeyQueryChange={setKeyQuery}
        hideSingleReference={hideSingleReference}
        onHideSingleReferenceChange={setHideSingleReference}
        stats={{ nodes: laid.nodes.length, edges: laid.edges.length, orphans: laid.orphans.length }}
      />
      <main className="canvas">
        <div className="mode-toggle" role="tablist">
          <button
            role="tab"
            className={mode === "reducers" ? "is-active" : ""}
            onClick={() => toggleMode("reducers")}
          >
            Reducers
          </button>
          <button
            role="tab"
            className={mode === "shared" ? "is-active" : ""}
            onClick={() => toggleMode("shared")}
          >
            Shared state
            {graph.sharedStorages && graph.sharedStorages.length > 0 && (
              <span className="mode-toggle-badge">{graph.sharedStorages.length}</span>
            )}
          </button>
        </div>

        {mode === "shared" && laid.nodes.length === 0 && (
          <div className="empty-overlay">
            <p>No shared storages match the current filters.</p>
          </div>
        )}

        <ReactFlow
          nodes={laid.nodes}
          edges={laid.edges}
          nodeTypes={nodeTypes}
          fitView
          fitViewOptions={{ duration: 300 }}
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

        {mode === "reducers" && (
          <button className="search-pill" onClick={() => setSearchOpen(true)} title="Search (⌘K or /)">
            <span>Search</span>
            <kbd>⌘K</kbd>
          </button>
        )}
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

      {selectedStorage && (
        <SharedStorageDrawer
          graph={graph}
          storage={selectedStorage}
          onClose={() => setSelectedId(null)}
          onNavigateToReducer={focusNode}
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
