# tca-graph

**Visualise your TCA architecture as graph and Lint it.**

<img width="800" height="466" alt="demotrca" src="https://github.com/user-attachments/assets/fa662abf-6e9b-4214-a394-2823c68c56d3" />


[![Release](https://img.shields.io/github/v/release/tornikegomareli/tca-graph)](https://github.com/tornikegomareli/tca-graph/releases/latest)
[![Swift 5.10+](https://img.shields.io/badge/Swift-5.10+-F05138.svg?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![macOS 13+ arm64](https://img.shields.io/badge/macOS-13%2B%20arm64-007AFF.svg?style=flat&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-E8E2D6.svg?style=flat)](https://swift.org/package-manager/)
[![Homebrew](https://img.shields.io/badge/Homebrew-tornikegomareli%2Ftca--graph-FBB040.svg?style=flat&logo=homebrew&logoColor=white)](https://github.com/tornikegomareli/homebrew-tca-graph)
[![License: MIT](https://img.shields.io/badge/License-MIT-A78BFA.svg?style=flat)](LICENSE)

CLI + interactive web viewer for Swift codebases that use [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). Walks the source with SwiftSyntax, renders the reducer composition and your shared state as a graph.

```bash
tca-graph serve ~/Code/MyApp        # explore the graph in your browser
tca-graph check ~/Code/MyApp        # lint architecture, fails CI on budget violations
```

## Install

macOS 13+ on Apple Silicon

**Homebrew**

```bash
brew tap tornikegomareli/tca-graph
brew install tca-graph
```

**Curl**

```bash
curl -sSL https://raw.githubusercontent.com/tornikegomareli/tca-graph/main/install.sh | bash
```

**Mint**

```bash
mint install tornikegomareli/tca-graph
```

**From source**

```bash
git clone https://github.com/tornikegomareli/tca-graph
cd tca-graph
(cd viewer && npm install && npm run build)   # populates Sources/TCAGraphCLI/Resources/Viewer
swift build -c release
```

### Two graph views

The reducer view shows every `@Reducer` in your codebase as a card sized by complexity. Edges encode composition kind — blue `Scope`, green `ifLet`, purple `ifCaseLet`, orange `forEach`. `@Presents` modifiers come through as animated dashed edges. Module color coding so same-module reducers read together at a glance.

The shared-state view is a second, orthogonal graph. Nodes are `@Shared(.appStorage(...))` / `.inMemory(...)` / `.fileStorage(...)` storage keys; edges connect them to every reducer whose state binds them. Reveals coupling that the reducer tree can't show — features that touch the same key are silently coupled and Xcode never surfaces it.

### A drilldown drawer with editor deep-links

Click any node for tabs covering State (with `@Presents` / `@Shared` flags), Actions (including nested `View` / `Internal` / `Delegate` enums), Dependencies, Complexity (score breakdown plus risks), and Graph (parents and children, clickable to navigate). 

### An architectural-budget linter

`tca-graph check` walks the graph and emits diagnostics when reducers cross size thresholds, too many fields / actions / children, modifier-chain depth past 4, Destination enums past 8 cases — or when the graph itself violates structural rules like cycles or mutual modal presentations. Runs at the speed of SwiftSyntax (no compile), exits with a CI-friendly code, and outputs in formats Xcode and GitHub Actions parse.

## Commands

### `serve` — interactive viewer

```bash
tca-graph serve <path> [-p <port>] [--no-open] [--viewer <dist-path>]
```

Analyzes the project in-process, starts a local HTTP server on `127.0.0.1:8765`, opens your default browser. The viewer reads the analyzed graph from memory — no JSON files written.

### `analyze` — emit JSON

```bash
tca-graph analyze <path> [-o <file>]
```

Same analysis, writes the canonical graph JSON to stdout (or a file with `-o`). Useful for CI pipelines, third-party renderers, or piping into `jq`.

### `check` — architectural-budget linter

```bash
tca-graph check <path> [--config <file>] [--format text|xcode|github|json]
```

Reads `.tca-graph.yml` (or built-in defaults), prints diagnostics in the requested format, exits `0` clean, `1` warnings only, `2` errors. The default config search looks for `.tca-graph.yml` then `.tca-graph.yaml` at the project root.

### `init-budgets` — snapshot today's max as the baseline

```bash
tca-graph init-budgets <path> [--force]
```

Writes a `.tca-graph.yml` whose budgets are exactly the codebase's current maximum metrics. The standard ratchet: from this point on, no PR can push any reducer past where you started. Run once when adopting the linter, commit the result, tighten thresholds over time.

## `.tca-graph.yml`

```yaml
budgets:
  max_fields_per_reducer: 40
  max_actions_per_reducer: 30
  max_children_per_reducer: 10
  max_chain_depth: 4
  max_destination_cases: 8

rules:
  cycle: error
  mutual_presentation: error
  destination_overflow: error
  deep_chain: error
  many_fields: warning
  many_actions: warning
  many_children: warning
```

## Xcode integration

Add a Run Script Build Phase:

```bash
if which tca-graph >/dev/null; then
    tca-graph check "${SRCROOT}" --format xcode
else
    echo "warning: tca-graph not installed — install from https://github.com/tornikegomareli/tca-graph"
fi
```

`--format xcode` emits diagnostics in the `<path>:<line>:<col>: warning|error: <message>` shape Xcode parses, so violations show up inline in the editor and Issue Navigator. Same as a SwiftLint finding.

## GitHub Actions integration

```yaml
- name: tca-graph check
  run: tca-graph check . --format github
```

`--format github` outputs `::warning file=...,line=N,col=M::message` annotation lines, so violations show up on the PR diff and in the Actions summary.

## What it analyzes

| Surface | Detected |
|---|---|
| Reducers | `@Reducer` macro, `ReducerProtocol` conformance, `@Reducer enum` destination patterns |
| State | Fields with `@Presents` / `@Shared` flags |
| Actions | Cases plus nested `View` / `Internal` / `Delegate` enums |
| Composition | `Scope`, `.ifLet`, `.ifCaseLet`, `.forEach` from the `body:` DSL |
| Shared storage | `.appStorage` / `.inMemory` / `.fileStorage` aggregated across the codebase |
| Dependencies | Every `@Dependency(\.foo)` keypath per reducer |
| Extensions | Cross-file `extension MyReducer { ... }` contributions merged into the owning reducer |

## What it doesn't

- **Doesn't compile your project.** Type information is syntactic only — the right tradeoff for architecture browsing, not for refactoring tools.
- **Doesn't track read-vs-write on `@Shared`.** Future work; reports references regardless of how they're accessed.
- **TCA 2.0 support is pending.** The 2.0 beta introduces a `@Feature` macro replacing `@Reducer`. Tracked at issue #2; will land once the 2.0 API stabilizes. Point-Free's 1.x compatibility shim means existing projects stay parseable through the migration.
- **Apple Silicon only.** Linux support is gated on swapping `Network.framework` for an NIO/sockets transport.

## License

[MIT](LICENSE)
