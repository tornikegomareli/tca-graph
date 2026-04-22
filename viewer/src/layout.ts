import dagre from "@dagrejs/dagre";
import type { Edge, Node } from "@xyflow/react";
import type { EdgeData, EdgeKind, Graph, NodeData, SharedStorageKind } from "./types";

const NODE_WIDTH = 280;
const NODE_HEIGHT = 200;

const STORAGE_NODE_WIDTH = 240;
const STORAGE_NODE_HEIGHT = 72;
const SLIM_REDUCER_WIDTH = 220;
const SLIM_REDUCER_HEIGHT = 64;

/// Fixed palette for the shared-state node badges — users should learn
/// which color means which storage kind, so we don't hash these.
export const storageKindStyle: Record<SharedStorageKind, { fg: string; bg: string; label: string }> = {
  appStorage:  { fg: "#9bb6ef", bg: "rgba(91,141,239,0.18)",  label: "app" },
  inMemory:    { fg: "#4fd3ae", bg: "rgba(16,172,132,0.18)",  label: "mem" },
  fileStorage: { fg: "#ffb280", bg: "rgba(230,126,34,0.18)",  label: "file" },
  other:       { fg: "#c291e4", bg: "rgba(142,68,173,0.18)",  label: "other" },
};

export function moduleStyle(moduleId: string): { fg: string; bg: string; border: string } {
  let h = 0;
  for (let i = 0; i < moduleId.length; i++) {
    h = ((h << 5) - h + moduleId.charCodeAt(i)) | 0;
  }
  const hue = ((h % 360) + 360) % 360;
  return {
    fg: `hsl(${hue}, 75%, 72%)`,
    bg: `hsla(${hue}, 65%, 50%, 0.18)`,
    border: `hsla(${hue}, 65%, 55%, 0.35)`,
  };
}

const edgeStyle: Record<EdgeKind, { stroke: string; strokeDasharray?: string; label: string }> = {
  scope:     { stroke: "#2e86de",                         label: "scope" },
  ifLet:     { stroke: "#10ac84",                         label: "ifLet" },
  ifCaseLet: { stroke: "#8e44ad",                         label: "ifCaseLet" },
  forEach:   { stroke: "#e67e22", strokeDasharray: "0",   label: "forEach" },
  combine:   { stroke: "#7f8c8d", strokeDasharray: "3 3", label: "combine" },
};

export interface LaidOutGraph {
  nodes: Node[];
  edges: Edge[];
  orphans: string[];
  /// The filtered raw graph data used to lay out the visualization. Exposed so that
  /// hover/selection neighborhoods and drawer parent/child lists respect the active
  /// module + edge-kind filters rather than the full unfiltered graph.
  filtered: { nodes: NodeData[]; edges: EdgeData[] };
}

export interface LayoutOptions {
  modules?: Set<string>;
  edgeKinds?: Set<EdgeKind>;
}

export interface ViewOptions {
  focusIds?: Set<string> | null;
  selectedId?: string | null;
}

export function layoutGraph(graph: Graph, filters: LayoutOptions): LaidOutGraph {
  const moduleById = new Map(graph.modules.map((m) => [m.id, m]));

  const visibleNodes = graph.nodes.filter(
    (n) => !filters.modules || filters.modules.has(n.moduleId)
  );
  const visibleIDs = new Set(visibleNodes.map((n) => n.id));

  const visibleEdges = graph.edges.filter((e) => {
    if (!visibleIDs.has(e.sourceId)) return false;
    if (!visibleIDs.has(e.targetId)) return false;
    if (filters.edgeKinds && !filters.edgeKinds.has(e.kind)) return false;
    return true;
  });

  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: "TB", nodesep: 60, ranksep: 100, marginx: 40, marginy: 40 });
  g.setDefaultEdgeLabel(() => ({}));

  for (const node of visibleNodes) {
    g.setNode(node.id, { width: NODE_WIDTH, height: NODE_HEIGHT });
  }
  for (const edge of visibleEdges) {
    g.setEdge(edge.sourceId, edge.targetId);
  }

  dagre.layout(g);

  const rfNodes: Node[] = visibleNodes.map((node) => {
    const laid = g.node(node.id);
    const moduleName = moduleById.get(node.moduleId)?.name ?? node.moduleId;
    return {
      id: node.id,
      type: "reducer",
      position: { x: laid.x - NODE_WIDTH / 2, y: laid.y - NODE_HEIGHT / 2 },
      data: { node, moduleName, faded: false, selected: false },
    };
  });

  const rfEdges: Edge[] = visibleEdges.map((e) => makeEdge(e));

  const targeted = new Set(visibleEdges.map((e) => e.targetId));
  const orphans = visibleNodes.filter((n) => !targeted.has(n.id)).map((n) => n.id);

  return {
    nodes: rfNodes,
    edges: rfEdges,
    orphans,
    filtered: { nodes: visibleNodes, edges: visibleEdges },
  };
}

function makeEdge(e: EdgeData): Edge {
  const style = edgeStyle[e.kind];
  return {
    id: e.id,
    source: e.sourceId,
    target: e.targetId,
    type: "smoothstep",
    animated: e.presentation,
    data: { kind: e.kind, presentation: e.presentation, sourceId: e.sourceId, targetId: e.targetId },
    // No default label — color already encodes kind, target node name shows destination.
    // Full statePath / actionPath is still in the drawer's Graph tab when a node is selected.
    style: {
      stroke: style.stroke,
      strokeWidth: e.presentation ? 2 : 1.5,
      strokeDasharray: e.presentation ? "4 2" : style.strokeDasharray,
    },
  };
}

/// Second pass: takes an already-laid graph and only updates className/data to reflect
/// the current hover/selection state. Reuses position objects and edge styles so
/// React Flow doesn't re-run its layout or animate positions on every pointer move.
export function applyViewState(
  laid: LaidOutGraph,
  view: ViewOptions
): LaidOutGraph {
  const focus = view.focusIds && view.focusIds.size > 0 ? view.focusIds : null;
  const selectedId = view.selectedId ?? null;

  const nodes: Node[] = laid.nodes.map((n) => {
    const faded = focus !== null && !focus.has(n.id);
    const selected = selectedId === n.id;
    const existing = (n.data ?? {}) as { faded?: boolean; selected?: boolean };
    if (existing.faded === faded && existing.selected === selected) {
      return n; // stable reference when nothing changed
    }
    return {
      ...n,
      className: `${faded ? "is-faded" : ""} ${selected ? "is-selected" : ""}`.trim(),
      data: { ...n.data, faded, selected },
    };
  });

  const edges: Edge[] = laid.edges.map((e) => {
    const d = (e.data ?? {}) as { sourceId?: string; targetId?: string };
    const inFocus = focus === null || (d.sourceId && d.targetId
      ? focus.has(d.sourceId) && focus.has(d.targetId)
      : true);
    const desired = inFocus ? "" : "is-faded";
    if (e.className === desired) return e;
    return { ...e, className: desired };
  });

  return { nodes, edges, orphans: laid.orphans, filtered: laid.filtered };
}


// ----------------------------------------------------------------------------
// Shared-state view
// ----------------------------------------------------------------------------

export interface SharedLayoutOptions {
  modules?: Set<string>;
  storageKinds?: Set<SharedStorageKind>;
  keyQuery?: string;
  hideSingleReference?: boolean;
}

/// Second, orthogonal graph: nodes are @Shared storage keys on the left,
/// referenced reducers on the right, one edge per binding. Makes coupling
/// through shared state legible — which reducers touch the same storage?
export function layoutSharedGraph(graph: Graph, filters: SharedLayoutOptions): LaidOutGraph {
  const moduleById = new Map(graph.modules.map((m) => [m.id, m]));
  const nodeById = new Map(graph.nodes.map((n) => [n.id, n]));
  const storages = graph.sharedStorages ?? [];

  const query = (filters.keyQuery ?? "").trim().toLowerCase();

  const visibleStorages = storages.filter((s) => {
    if (filters.storageKinds && !filters.storageKinds.has(s.kind)) return false;
    if (query && !s.key.toLowerCase().includes(query)) return false;
    if (filters.hideSingleReference && s.referencedBy.length <= 1) return false;
    if (filters.modules) {
      const anyInModule = s.referencedBy.some((r) => {
        const n = nodeById.get(r.nodeId);
        return n ? filters.modules!.has(n.moduleId) : false;
      });
      if (!anyInModule) return false;
    }
    return true;
  });

  // Unique reducer ids referenced by at least one visible storage.
  const visibleReducerIds = new Set<string>();
  for (const s of visibleStorages) {
    for (const r of s.referencedBy) {
      if (!nodeById.has(r.nodeId)) continue;
      if (filters.modules) {
        const n = nodeById.get(r.nodeId)!;
        if (!filters.modules.has(n.moduleId)) continue;
      }
      visibleReducerIds.add(r.nodeId);
    }
  }

  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: "LR", nodesep: 22, ranksep: 220, marginx: 40, marginy: 40 });
  g.setDefaultEdgeLabel(() => ({}));

  for (const s of visibleStorages) {
    g.setNode(s.id, { width: STORAGE_NODE_WIDTH, height: STORAGE_NODE_HEIGHT });
  }
  for (const id of visibleReducerIds) {
    g.setNode(id, { width: SLIM_REDUCER_WIDTH, height: SLIM_REDUCER_HEIGHT });
  }

  // Edges: storage → each reducer that binds it (skip if reducer is filtered out).
  const rawEdges: { id: string; sourceId: string; targetId: string; fieldName: string }[] = [];
  for (const s of visibleStorages) {
    for (const r of s.referencedBy) {
      if (!visibleReducerIds.has(r.nodeId)) continue;
      rawEdges.push({
        id: `sharedEdge:${s.id}→${r.nodeId}:${r.fieldName}`,
        sourceId: s.id,
        targetId: r.nodeId,
        fieldName: r.fieldName,
      });
      g.setEdge(s.id, r.nodeId);
    }
  }

  dagre.layout(g);

  const storageNodes: Node[] = visibleStorages.map((s) => {
    const laid = g.node(s.id);
    return {
      id: s.id,
      type: "sharedStorage",
      position: { x: laid.x - STORAGE_NODE_WIDTH / 2, y: laid.y - STORAGE_NODE_HEIGHT / 2 },
      data: { storage: s, faded: false, selected: false },
    };
  });

  const reducerNodes: Node[] = [...visibleReducerIds].map((id) => {
    const laid = g.node(id);
    const node = nodeById.get(id)!;
    const moduleName = moduleById.get(node.moduleId)?.name ?? node.moduleId;
    return {
      id,
      type: "reducer",
      position: { x: laid.x - SLIM_REDUCER_WIDTH / 2, y: laid.y - SLIM_REDUCER_HEIGHT / 2 },
      data: { node, moduleName, slim: true, faded: false, selected: false },
    };
  });

  const rfEdges: Edge[] = rawEdges.map((e) => ({
    id: e.id,
    source: e.sourceId,
    target: e.targetId,
    type: "smoothstep",
    // No label — drawer's "Referenced by" list shows field names with context.
    data: { sourceId: e.sourceId, targetId: e.targetId, fieldName: e.fieldName },
    style: { stroke: "#5b8def", strokeWidth: 1.4, strokeDasharray: "4 3" },
  }));

  // `filtered` is expected by applyViewState; we surface the raw pieces for parity.
  const pseudoEdges: EdgeData[] = rawEdges.map((e) => ({
    id: e.id,
    sourceId: e.sourceId,
    targetId: e.targetId,
    kind: "scope",
    presentation: false,
  }));
  const filteredNodes: NodeData[] = [...visibleReducerIds]
    .map((id) => nodeById.get(id))
    .filter((n): n is NodeData => Boolean(n));

  return {
    nodes: [...storageNodes, ...reducerNodes],
    edges: rfEdges,
    orphans: [],
    filtered: { nodes: filteredNodes, edges: pseudoEdges },
  };
}
