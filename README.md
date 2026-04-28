# tca-graph

Interactive architecture visualizer and architectural-budget linter for Swift codebases that use [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). Point it at a project, see how your reducers compose, see where the heaviest features live, and fail PRs that push past the budgets you set.

```bash
tca-graph serve ~/Code/MyApp        # explore the graph in your browser
tca-graph check ~/Code/MyApp        # lint the architecture; fails CI on budget violations
```

No Xcode project required, no compilation step. SwiftSyntax-only analysis runs in seconds against any TCA codebase.

## What it does

**An interactive graph of every reducer in your codebase.** Each `@Reducer` becomes a card showing module, state field count, action count, and dependency injections. Edges encode composition kind: blue for `Scope`, green for `ifLet`, purple for `ifCaseLet`, orange for `forEach`, with presentation modifiers (`@Presents` + `.ifLet(\.$state, …)`) animated and dashed. Node size scales with a complexity score so the heaviest reducers visibly dominate.

**A second graph for shared state.** Toggle "Shared state" at the top of the canvas and the same data pivots: nodes are `@Shared(.appStorage(...))` / `.inMemory(...)` / `.fileStorage(...)` storage keys, edges connect them to every reducer whose state binds them. Reveals coupling that the reducer tree can't show — features that touch the same key are silently coupled in a way Xcode never surfaces.

**Drilldown drawer with editor deep-links.** Click any reducer for tabs covering State (with `@Presents` / `@Shared` flags), Actions (including nested `View` / `Internal` / `Delegate` enums), Dependencies, Complexity (score breakdown + risks), and Graph (parents and children, clickable to navigate). Open the file in Cursor, VS Code, or Zed via URL scheme.

**An architectural-budget linter.** `tca-graph check` walks the graph and emits diagnostics when reducers cross size thresholds (too many fields / actions / children, modifier-chain depth past 4, Destination enums past 8 cases) or when the graph itself violates rules (cycles, mutual modal presentations). Outputs render as Xcode warnings/errors when wired into a Run Script Build Phase, or as PR annotations under GitHub Actions.

## Install

macOS 13+ on Apple Silicon (arm64). Pick whichever fits your workflow.

### Homebrew

```bash
brew tap tornikegomareli/tca-graph
brew install tca-graph
```

### Curl one-liner

```bash
curl -sSL https://raw.githubusercontent.com/tornikegomareli/tca-graph/main/install.sh | bash
```

Installs into `~/.local/bin` by default; pass `--prefix /usr/local` (with `sudo`) to install system-wide. The script verifies the SHA-256 checksum of the downloaded tarball before extracting.

### Mint

```bash
mint install tornikegomareli/tca-graph
```

The viewer is bundled as an SPM resource, so `mint install` produces a self-contained binary — no separate npm step.

### Manual tarball

Releases ship a `tca-graph-<version>-macos-arm64.tar.gz` next to a matching `.sha256` checksum on every tag. Download from the [releases page](https://github.com/tornikegomareli/tca-graph/releases/latest), verify, extract, and put `bin/tca-graph` on your PATH (keep the adjacent `.bundle` directory next to it).

### From source

Requires Swift 5.10+ and Node 18+.

```bash
git clone https://github.com/tornikegomareli/tca-graph.git
cd tca-graph
(cd viewer && npm install && npm run build)   # populates Sources/TCAGraphCLI/Resources/Viewer
swift build -c release

# Run it directly, or symlink onto your PATH.
./.build/release/tca-graph serve ~/path/to/your/TCAProject
```

## Commands

### `serve` — interactive viewer

```bash
tca-graph serve <path> [-p <port>] [--no-open] [--viewer <dist-path>]
```

Analyzes the project in-process, starts a local HTTP server on `127.0.0.1:8765`, and opens your default browser. The viewer reads the analyzed graph from memory (no JSON files written). `--no-open` skips the browser launch (useful for headless test runs); `--port` changes the listen port; `--viewer` overrides the search for the React bundle if it isn't alongside the binary.

### `analyze` — emit JSON

```bash
tca-graph analyze <path> [-o <file>]
```

Runs the same analysis but writes the canonical graph JSON to stdout (or a file with `-o`). Use this for CI pipelines, third-party renderers, or piping into `jq` for custom queries.

### `check` — architectural-budget linter

```bash
tca-graph check <path> [--config <file>] [--format text|xcode|github|json]
```

Walks the graph, applies the rules in `.tca-graph.yml` (or built-in defaults), prints diagnostics in the requested format, and exits with a CI-friendly status (`0` clean, `1` warnings only, `2` errors). The default config search looks for `.tca-graph.yml` then `.tca-graph.yaml` at the project root; `--config` overrides it.

The four formats:
- `text` — human-readable terminal output with severity icons and a summary line.
- `xcode` — the format Xcode parses for inline diagnostics in the editor and Issue Navigator.
- `github` — annotation lines that GitHub Actions surfaces inline on the PR diff.
- `json` — structured output for dashboards and custom tooling.

### `init-budgets` — snapshot today's max as the baseline

```bash
tca-graph init-budgets <path> [--force]
```

Analyzes the project and writes a `.tca-graph.yml` whose budgets are exactly the codebase's current maximum metrics. The standard ratchet pattern: from this point on, no PR can push any reducer past where you started. Run it once when adopting the linter, commit the result, tighten thresholds over time as the architecture improves.

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

Every key is optional. Missing budgets fall back to the defaults shown above; missing rules use their built-in default severity (cycle / mutual presentation / destination overflow / deep chain default to `error`, the rest to `warning`). Severity is `warning` or `error`.

## Xcode integration

Add a Run Script Build Phase to your target:

```bash
if which tca-graph >/dev/null; then
    tca-graph check "${SRCROOT}" --format xcode
else
    echo "warning: tca-graph not installed — install from https://github.com/tornikegomareli/tca-graph"
fi
```

`tca-graph check --format xcode` emits diagnostics in the format Xcode parses (`<path>:<line>:<col>: warning|error: <message>`), so violations show inline in the editor and in the Issue Navigator with the same UX as compiler warnings or SwiftLint findings.

## GitHub Actions integration

```yaml
- name: tca-graph check
  run: tca-graph check . --format github
```

The `--format github` output uses GitHub's annotation syntax (`::warning file=...,line=N,col=M::message`), so violations show up as inline annotations on the PR diff and as warnings/errors in the Actions summary. Combine with the Action's `continue-on-error` semantics and exit codes to gate merges.

## What it analyzes

The parser uses [SwiftSyntax](https://github.com/swiftlang/swift-syntax) and runs without compiling the project.

**Reducers.** Detects both the modern `@Reducer` macro and the older `ReducerProtocol` conformance, plus the `@Reducer enum Destination` destination-enum pattern. Cross-file extension contributions (declaring `Action` in a separate `extension MyReducer { … }`) are merged into the owning reducer.

**State and actions.** State fields with `@Presents` / `@Shared(...)` flags, action cases including nested `View` / `Internal` / `Delegate` enums.

**Composition edges.** `Scope`, `.ifLet`, `.ifCaseLet`, `.forEach` from the `body:` computed property. Modifier chains (`Reduce { }.ifLet(...).forEach(...)`) are unchained into individual edges, with chain depth tracked per edge for the deep-chain risk.

**Shared storage.** Every `@Shared(.appStorage("key"))`, `.inMemory("key")`, and `.fileStorage(.documentsDirectory.appending(component: "key.json"))` is normalized into a canonical `(kind, key)` pair and aggregated across the codebase.

**Dependencies.** Every `@Dependency(\.foo)` keypath per reducer.

## What it doesn't

- **Doesn't compile your project.** Type information is syntactic only — fully-qualified types across modules are resolved by name + import scope, not by semantic inspection. For architecture browsing this is the right tradeoff; for refactoring tools it would be insufficient.

- **Doesn't track read-vs-write on `@Shared`.** Future work; v1 reports references regardless of how the reducer accesses them.

- **TCA 2.0 support is pending.** The 2.0 beta introduces a `@Feature` macro that replaces `@Reducer`. Tracked at issue #2; will land once the 2.0 API stabilizes. The 1.x compatibility shim Point-Free ships means existing projects keep working with this tool through the migration period.

## Roadmap

Past 0.4.0, the next high-value features (in rough order):

- **Inline source preview** in the drawer — read the reducer's actual body without leaving the viewer.
- **Dependency fan-out matrix** — rows × columns view of reducers × `@Dependency` keypaths, surfacing implicit couplings and refactor blast radius.
- **`_printChanges` replay** — paste a runtime log, the viewer animates the action flow on the graph.
- **Live re-analysis via file watcher** — graph updates in milliseconds as you save.
- **Graph diff between git refs** — `tca-graph diff origin/main HEAD` for PR-time architectural review.

Open issues track the rest.

## Status

0.4.0. Not yet 1.0 — JSON schema, CLI surface, and `.tca-graph.yml` shape may still evolve based on real-world feedback. Battle-tested against a 23-reducer / 38-module TCA codebase.

## License

TBD before 1.0.
