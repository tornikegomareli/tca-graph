import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { NodeData } from "../types";
import { moduleStyle } from "../layout";

export interface ReducerNodeData extends Record<string, unknown> {
  node: NodeData;
  moduleName: string;
  faded?: boolean;
  selected?: boolean;
  /// Width / height computed by layout based on complexity score. Applied as inline
  /// style so the heatmap-by-size effect overrides the static CSS width.
  width?: number;
  height?: number;
  /// When true, render a compact variant used in the shared-state view where the
  /// reducer is a secondary citizen — no stat row, no chips, just module + name.
  slim?: boolean;
}

const dialectColor: Record<string, string> = {
  macro: "#5b8def",
  protocol: "#9b59b6",
  legacy: "#95a5a6",
  unknown: "#7f8c8d",
};

export function ReducerNode({ data }: NodeProps) {
  const { node, moduleName, selected, slim, width, height } = data as ReducerNodeData;
  const accent = dialectColor[node.tcaDialect] ?? dialectColor.unknown;
  const mod = moduleStyle(node.moduleId);
  // Inline size from layout so the heatmap-by-complexity overrides the CSS width.
  // Fall back to the slim variant's hardcoded shape and otherwise to undefined so
  // CSS defaults apply.
  const sizeStyle: React.CSSProperties | undefined = !slim && width && height
    ? { width, minHeight: height }
    : undefined;

  if (slim) {
    return (
      <div
        className={`reducer-node is-slim ${selected ? "is-selected" : ""}`}
        style={{ borderColor: accent }}
      >
        <Handle type="target" position={Position.Left} />
        <div className="rn-slim-inner">
          <span
            className="rn-module"
            title={moduleName}
            style={{ color: mod.fg, background: mod.bg, borderColor: mod.border }}
          >
            {moduleName}
          </span>
          <span className="rn-name" title={node.name}>{node.name}</span>
        </div>
        <Handle type="source" position={Position.Right} />
      </div>
    );
  }

  const fieldCount = node.state?.fields.length ?? 0;
  const caseCount = node.action?.cases.length ?? 0;
  const nestedCount = node.action?.nestedEnums.length ?? 0;
  const depCount = node.dependencies.length;

  return (
    <div
      className={`reducer-node ${selected ? "is-selected" : ""}`}
      style={{ borderColor: accent, ...sizeStyle }}
    >
      <Handle type="target" position={Position.Top} />
      <div className="rn-header" style={{ borderColor: accent }}>
        <div
          className="rn-module"
          title={moduleName}
          style={{ color: mod.fg, background: mod.bg, borderColor: mod.border }}
        >
          {moduleName}
        </div>
        <div className="rn-title-row">
          <span className="rn-name">{node.name}</span>
          {node.usesBinding && <span className="rn-chip rn-chip-binding" title="Uses BindingReducer">binding</span>}
          {node.risks && node.risks.length > 0 && (
            <span
              className="rn-chip rn-chip-risk"
              title={`${node.risks.length} compile-time risk${node.risks.length > 1 ? "s" : ""} — see Complexity tab`}
            >
              risk{node.risks.length > 1 ? ` ${node.risks.length}` : ""}
            </span>
          )}
        </div>
      </div>

      <div className="rn-stats">
        <Stat label="fields" value={fieldCount} />
        <Stat label="actions" value={caseCount} />
        {nestedCount > 0 && <Stat label="nested" value={nestedCount} />}
        <Stat label="deps" value={depCount} />
      </div>

      {node.dependencies.length > 0 && (
        <div className="rn-deps">
          {node.dependencies.slice(0, 4).map((d) => (
            <span key={d.keyPath} className="rn-chip rn-chip-dep" title={d.keyPath}>
              \.{d.keyPath}
            </span>
          ))}
          {node.dependencies.length > 4 && (
            <span className="rn-chip rn-chip-more">+{node.dependencies.length - 4}</span>
          )}
        </div>
      )}

      {node.state && node.state.fields.some((f) => f.presentation || f.childRef) && (
        <div className="rn-children">
          {node.state.fields
            .filter((f) => f.presentation || f.childRef)
            .slice(0, 6)
            .map((f) => (
              <span
                key={f.name}
                className={`rn-chip ${f.presentation ? "rn-chip-pres" : "rn-chip-child"}`}
                title={f.type}
              >
                {f.name}
              </span>
            ))}
        </div>
      )}

      <Handle type="source" position={Position.Bottom} />
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rn-stat">
      <span className="rn-stat-value">{value}</span>
      <span className="rn-stat-label">{label}</span>
    </div>
  );
}
