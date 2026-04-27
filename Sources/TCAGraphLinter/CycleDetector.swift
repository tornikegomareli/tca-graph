import Foundation
import TCAGraphModel

/// Pure graph analyses over a `Graph`'s edge list. No I/O, no SwiftSyntax.
public enum CycleDetector {

  /// Detect any cycles in the reducer composition graph. Returns each cycle as a list
  /// of node IDs in traversal order (the first node is repeated only once at the start).
  ///
  /// Reducer trees in TCA are supposed to be DAGs — cycles indicate either a bug
  /// (the parser couldn't disambiguate a same-named child) or a real architectural
  /// problem (rare but possible via case-paths and shared destination enums).
  public static func cycles(in nodes: [Node], edges: [Edge]) -> [[String]] {
    let nodeIDs = Set(nodes.map(\.id))
    var adjacency: [String: [String]] = [:]
    for edge in edges where nodeIDs.contains(edge.sourceId) && nodeIDs.contains(edge.targetId) {
      adjacency[edge.sourceId, default: []].append(edge.targetId)
    }

    var color: [String: Color] = [:]      // unvisited → gray (on stack) → black (done)
    var path: [String] = []
    var cycles: [[String]] = []
    // Use a Set of cycles by canonical key to dedupe; same cycle reachable from
    // multiple roots otherwise gets reported multiple times.
    var seen = Set<String>()

    for nodeId in nodes.map(\.id) {
      if color[nodeId] != .black {
        dfs(from: nodeId, adjacency: adjacency, color: &color, path: &path, cycles: &cycles, seen: &seen)
      }
    }

    return cycles
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

  private enum Color { case gray, black }

  private static func dfs(
    from start: String,
    adjacency: [String: [String]],
    color: inout [String: Color],
    path: inout [String],
    cycles: inout [[String]],
    seen: inout Set<String>
  ) {
    color[start] = .gray
    path.append(start)
    for next in adjacency[start] ?? [] {
      switch color[next] {
      case .gray:
        // Found a back-edge — extract the cycle from the path.
        if let startIdx = path.firstIndex(of: next) {
          let cycle = Array(path[startIdx...])
          let key = canonicalCycleKey(cycle)
          if seen.insert(key).inserted {
            cycles.append(cycle)
          }
        }
      case .black:
        continue
      case .none:
        dfs(from: next, adjacency: adjacency, color: &color, path: &path, cycles: &cycles, seen: &seen)
      }
    }
    path.removeLast()
    color[start] = .black
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
