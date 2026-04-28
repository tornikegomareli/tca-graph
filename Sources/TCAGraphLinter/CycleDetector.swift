import Foundation
import TCAGraphModel

/// Pure graph analyses over a `Graph`'s edge list. No I/O, no SwiftSyntax.
public enum CycleDetector {

  /// Detect every simple cycle in the reducer composition graph. Returns each cycle
  /// as a list of node IDs in traversal order (no node repeated; the start ID
  /// appears once at index 0).
  ///
  /// Reducer trees in TCA are supposed to be DAGs — cycles indicate either a bug
  /// (the parser couldn't disambiguate a same-named child) or a real architectural
  /// problem (rare but possible via case-paths and shared destination enums).
  ///
  /// Algorithm: for each candidate anchor node A, run DFS from A only following
  /// edges whose targets are >= A in lexicographic id order. When the DFS reaches
  /// A again, the path is a simple cycle whose smallest node is A — guaranteeing
  /// every simple cycle is reported exactly once at the anchor that's its smallest
  /// node, and overlapping cycles through shared nodes are all enumerated. This
  /// avoids the classic "blacken once" pitfall of basic 3-color DFS, which would
  /// drop the second cycle through any shared node.
  public static func cycles(in nodes: [Node], edges: [Edge]) -> [[String]] {
    let nodeIDs = Set(nodes.map(\.id))
    var adjacency: [String: [String]] = [:]
    for edge in edges where nodeIDs.contains(edge.sourceId) && nodeIDs.contains(edge.targetId) {
      adjacency[edge.sourceId, default: []].append(edge.targetId)
    }

    var allCycles: [[String]] = []
    var seenKeys = Set<String>()

    for anchor in nodes.map(\.id) {
      var path: [String] = [anchor]
      var onPath: Set<String> = [anchor]
      enumerate(
        anchor: anchor,
        current: anchor,
        adjacency: adjacency,
        path: &path,
        onPath: &onPath,
        cycles: &allCycles,
        seen: &seenKeys
      )
    }

    return allCycles
  }

  /// Detect mutual presentations: pairs of reducers that present each other modally.
  /// A presentation cycle of length 2 — a structurally distinct anti-pattern from a
  /// general cycle, so it gets its own report.
  public static func mutualPresentations(in edges: [Edge]) -> [(String, String)] {
    let presentationOnly = edges.filter(\.presentation)
    var seenPair = Set<String>()
    var pairs: [(String, String)] = []

    let bySource = Dictionary(grouping: presentationOnly, by: \.sourceId)

    for forward in presentationOnly {
      // Look for an edge in the opposite direction that's also a presentation edge.
      let reverseCandidates = bySource[forward.targetId] ?? []
      let hasReverse = reverseCandidates.contains { $0.targetId == forward.sourceId }
      guard hasReverse else { continue }
      let key = canonicalPair(forward.sourceId, forward.targetId)
      if seenPair.insert(key).inserted {
        pairs.append((forward.sourceId, forward.targetId))
      }
    }

    return pairs
  }

  // MARK: - Private

  /// DFS from a fixed anchor node. Records a cycle each time we re-enter the
  /// anchor; otherwise descends into neighbors that satisfy the lex-anchor
  /// constraint (`next >= anchor`). Critically does NOT mark nodes globally
  /// visited — a node can participate in multiple cycles and each must be
  /// reachable through this anchor's DFS.
  private static func enumerate(
    anchor: String,
    current: String,
    adjacency: [String: [String]],
    path: inout [String],
    onPath: inout Set<String>,
    cycles: inout [[String]],
    seen: inout Set<String>
  ) {
    for next in adjacency[current] ?? [] {
      if next == anchor {
        // Found a simple cycle anchored at `anchor`.
        let key = canonicalCycleKey(path)
        if seen.insert(key).inserted {
          cycles.append(path)
        }
        continue
      }
      // Restrict to cycles whose smallest node is `anchor`. Skipping nodes
      // smaller than the anchor means each simple cycle is enumerated exactly
      // once (at the anchor equal to its lex-min node).
      if next < anchor { continue }
      // Avoid revisiting nodes already on the current DFS path — that would
      // mean a non-simple cycle (loop containing a smaller cycle).
      if onPath.contains(next) { continue }

      path.append(next)
      onPath.insert(next)
      enumerate(
        anchor: anchor,
        current: next,
        adjacency: adjacency,
        path: &path,
        onPath: &onPath,
        cycles: &cycles,
        seen: &seen
      )
      path.removeLast()
      onPath.remove(next)
    }
  }

  /// Canonical key for cycle deduplication — rotates so the lexicographically smallest
  /// node is first, then joins. Two reports of the same cycle starting at different
  /// nodes collapse to one.
  private static func canonicalCycleKey(_ cycle: [String]) -> String {
    guard !cycle.isEmpty else { return "" }
    guard let minIdx = cycle.indices.min(by: { cycle[$0] < cycle[$1] }) else { return "" }
    let rotated = Array(cycle[minIdx...]) + Array(cycle[..<minIdx])
    return rotated.joined(separator: " → ")
  }

  private static func canonicalPair(_ a: String, _ b: String) -> String {
    a < b ? "\(a)|\(b)" : "\(b)|\(a)"
  }
}
