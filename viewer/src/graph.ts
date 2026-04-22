import type { EdgeData } from "./types";

export interface Neighborhood {
  self: string;
  ancestors: Set<string>;
  descendants: Set<string>;
  all: Set<string>;
  incomingEdges: EdgeData[];
  outgoingEdges: EdgeData[];
}

/// Walks the edge list to find all ancestors and descendants of a node.
/// Takes an edges array directly (rather than a full Graph) so callers can pass a
/// filtered slice when they want hover/selection to respect active filters.
export function buildNeighborhood(edges: EdgeData[], nodeId: string): Neighborhood {
  const incoming = new Map<string, EdgeData[]>();
  const outgoing = new Map<string, EdgeData[]>();
  for (const e of edges) {
    (outgoing.get(e.sourceId) ?? outgoing.set(e.sourceId, []).get(e.sourceId)!).push(e);
    (incoming.get(e.targetId) ?? incoming.set(e.targetId, []).get(e.targetId)!).push(e);
  }

  const ancestors = bfs(nodeId, (id) => (incoming.get(id) ?? []).map((e) => e.sourceId));
  const descendants = bfs(nodeId, (id) => (outgoing.get(id) ?? []).map((e) => e.targetId));

  const all = new Set<string>([nodeId, ...ancestors, ...descendants]);
  return {
    self: nodeId,
    ancestors,
    descendants,
    all,
    incomingEdges: incoming.get(nodeId) ?? [],
    outgoingEdges: outgoing.get(nodeId) ?? [],
  };
}

function bfs(start: string, neighbors: (id: string) => string[]): Set<string> {
  const seen = new Set<string>();
  const queue: string[] = neighbors(start);
  while (queue.length > 0) {
    const id = queue.shift()!;
    if (seen.has(id) || id === start) continue;
    seen.add(id);
    queue.push(...neighbors(id));
  }
  return seen;
}
