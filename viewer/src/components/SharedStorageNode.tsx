import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { SharedStorage } from "../types";
import { moduleStyle, storageKindStyle } from "../layout";

export interface SharedStorageNodeData extends Record<string, unknown> {
  storage: SharedStorage;
  selected?: boolean;
  faded?: boolean;
}

export function SharedStorageNode({ data }: NodeProps) {
  const { storage, selected } = data as SharedStorageNodeData;
  const kind = storageKindStyle[storage.kind];
  const border = moduleStyle(storage.id).border;

  return (
    <div
      className={`shared-node ${selected ? "is-selected" : ""}`}
      style={{ borderColor: border }}
    >
      <Handle type="target" position={Position.Left} />
      <div className="sn-inner">
        <span
          className="sn-kind"
          style={{ color: kind.fg, background: kind.bg }}
          title={storage.kind}
        >
          {kind.label}
        </span>
        <span className="sn-key" title={storage.rawDescriptor}>{storage.key}</span>
        <span className="sn-count" title={`${storage.referencedBy.length} references`}>
          {storage.referencedBy.length}
        </span>
      </div>
      <Handle type="source" position={Position.Right} />
    </div>
  );
}
