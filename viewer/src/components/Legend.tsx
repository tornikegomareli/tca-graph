import { useState } from "react";
import { storageKindStyle } from "../layout";
import type { ViewMode } from "./Sidebar";

interface Props {
  mode: ViewMode;
}

/// Small collapsible legend explaining what the colors mean in each view. Defaults
/// to open the first time the viewer loads so newcomers get oriented; users can
/// collapse it once they've learned the code.
export function Legend({ mode }: Props) {
  const [open, setOpen] = useState(true);

  return (
    <section className={`sb-section sb-legend ${open ? "is-open" : "is-closed"}`}>
      <button
        className="sb-section-header sb-legend-toggle"
        onClick={() => setOpen((o) => !o)}
      >
        <h2>Legend</h2>
        <span className="sb-legend-caret">{open ? "▾" : "▸"}</span>
      </button>
      {open && (mode === "reducers" ? <ReducerLegend /> : <SharedLegend />)}
    </section>
  );
}

function ReducerLegend() {
  return (
    <div className="lg-body">
      <LegendGroup title="Edges">
        <EdgeSample stroke="#2e86de" label="scope" description="always-present child" />
        <EdgeSample stroke="#10ac84" label="ifLet" description="optional child" />
        <EdgeSample stroke="#8e44ad" label="ifCaseLet" description="enum-case child" />
        <EdgeSample stroke="#e67e22" label="forEach" description="collection of children" />
        <EdgeSample stroke="#10ac84" dashed label="presentation" description="@Presents modal / sheet" />
      </LegendGroup>

      <LegendGroup title="State chips on nodes">
        <ChipSample className="rn-chip rn-chip-child" label="childState" description="embedded sub-feature" />
        <ChipSample className="rn-chip rn-chip-pres" label="@Presents" description="modal / sheet / cover" />
      </LegendGroup>
    </div>
  );
}

function SharedLegend() {
  return (
    <div className="lg-body">
      <LegendGroup title="Storage kinds">
        <ChipSample
          style={{ color: storageKindStyle.appStorage.fg, background: storageKindStyle.appStorage.bg }}
          label="app"
          description="UserDefaults (.appStorage)"
        />
        <ChipSample
          style={{ color: storageKindStyle.inMemory.fg, background: storageKindStyle.inMemory.bg }}
          label="mem"
          description="in-memory only"
        />
        <ChipSample
          style={{ color: storageKindStyle.fileStorage.fg, background: storageKindStyle.fileStorage.bg }}
          label="file"
          description="on-disk JSON"
        />
        <ChipSample
          style={{ color: storageKindStyle.other.fg, background: storageKindStyle.other.bg }}
          label="other"
          description="custom / non-factory"
        />
      </LegendGroup>
      <p className="lg-hint">
        An edge connects each storage to every reducer whose State binds it via <code>@Shared</code>.
      </p>
    </div>
  );
}

function LegendGroup({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="lg-group">
      <div className="lg-group-title">{title}</div>
      <ul className="lg-list">{children}</ul>
    </div>
  );
}

function EdgeSample({
  stroke,
  dashed,
  label,
  description,
}: {
  stroke: string;
  dashed?: boolean;
  label: string;
  description: string;
}) {
  return (
    <li>
      <svg className="lg-edge" width="28" height="10" aria-hidden>
        <line
          x1="0" y1="5" x2="28" y2="5"
          stroke={stroke}
          strokeWidth="2"
          strokeDasharray={dashed ? "4 2" : undefined}
        />
      </svg>
      <span className="lg-label">{label}</span>
      <span className="lg-desc">{description}</span>
    </li>
  );
}

function ChipSample({
  className,
  style,
  label,
  description,
}: {
  className?: string;
  style?: React.CSSProperties;
  label: string;
  description: string;
}) {
  return (
    <li>
      <span className={`lg-chip ${className ?? ""}`} style={style}>{label}</span>
      <span className="lg-desc">{description}</span>
    </li>
  );
}
