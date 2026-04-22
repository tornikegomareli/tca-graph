import { useEffect, useMemo, useRef, useState } from "react";
import type { NodeData } from "../types";
import { moduleStyle } from "../layout";

interface Props {
  nodes: NodeData[];
  moduleNameById: Map<string, string>;
  onSelect: (id: string) => void;
  onClose: () => void;
}

export function SearchOverlay({ nodes, moduleNameById, onSelect, onClose }: Props) {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => { inputRef.current?.focus(); }, []);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    const matched = q
      ? nodes.filter((n) => n.name.toLowerCase().includes(q) || moduleNameById.get(n.moduleId)?.toLowerCase().includes(q))
      : nodes;
    return matched.slice(0, 20);
  }, [query, nodes, moduleNameById]);

  useEffect(() => { setActive(0); }, [query]);

  const onKey = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "ArrowDown") { e.preventDefault(); setActive((i) => Math.min(results.length - 1, i + 1)); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setActive((i) => Math.max(0, i - 1)); }
    else if (e.key === "Enter") { e.preventDefault(); if (results[active]) onSelect(results[active].id); }
    else if (e.key === "Escape") { e.preventDefault(); onClose(); }
  };

  return (
    <div className="search-backdrop" onClick={onClose}>
      <div className="search-modal" onClick={(e) => e.stopPropagation()}>
        <input
          ref={inputRef}
          type="text"
          placeholder="Search reducers…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={onKey}
          className="search-input"
        />
        <ul className="search-results">
          {results.length === 0 && <li className="search-empty">No matches</li>}
          {results.map((n, i) => {
            const ms = moduleStyle(n.moduleId);
            const moduleName = moduleNameById.get(n.moduleId) ?? n.moduleId;
            return (
              <li
                key={n.id}
                className={`search-item ${i === active ? "is-active" : ""}`}
                onMouseEnter={() => setActive(i)}
                onClick={() => onSelect(n.id)}
              >
                <span
                  className="search-module"
                  style={{ color: ms.fg, background: ms.bg, borderColor: ms.border }}
                >
                  {moduleName}
                </span>
                <span className="search-name">{n.name}</span>
              </li>
            );
          })}
        </ul>
        <div className="search-hint">
          <span>↑↓ navigate</span>
          <span>↵ select</span>
          <span>esc close</span>
        </div>
      </div>
    </div>
  );
}
