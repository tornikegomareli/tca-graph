import dagre from "@dagrejs/dagre";
import type { Edge, Node } from "@xyflow/react";
import type { EdgeData, EdgeKind, Graph, NodeData } from "./types";

const NODE_WIDTH = 280;
const NODE_HEIGHT = 200;

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
    label: shortLabel(e),
    labelStyle: { fontSize: 10, fill: "#666" },
    labelBgStyle: { fill: "#fff", fillOpacity: 0.85 },
    labelBgPadding: [2, 3],
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

function shortLabel(e: EdgeData): string {
  const kindLabel = edgeStyle[e.kind].label;
  if (e.statePath) {
    // `\.foo` or `\.$foo` — strip the leading `\.` for tidier labels
    const clean = e.statePath.replace(/^\\\./, "");
    return `${kindLabel}  ${clean}`;
  }
  return kindLabel;
}
