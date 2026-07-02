'use client';

// Autocomplete de profissão — porta fiel do formulário legado (ranking + navegação por teclado).

import { useCallback, useEffect, useRef, useState } from 'react';
import { getProfissaoSuggestions } from '../domain/profissao-suggest';

export function ProfissaoAutocomplete({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [items, setItems] = useState<string[]>([]);
  const [active, setActive] = useState(-1);
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const blurTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const sync = useCallback((v: string) => {
    const next = getProfissaoSuggestions(v);
    setItems(next);
    setActive(next.length ? 0 : -1);
    setOpen(next.length > 0);
  }, []);

  const apply = (v: string) => {
    onChange(v);
    setOpen(false);
    setActive(-1);
    inputRef.current?.focus();
  };

  useEffect(() => {
    const onDocClick = (e: MouseEvent) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('click', onDocClick);
    return () => document.removeEventListener('click', onDocClick);
  }, []);

  function onKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (!items.length) return;
    if (e.key === 'Enter') {
      e.preventDefault();
      apply(items[active >= 0 ? active : 0]);
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActive((i) => Math.min(items.length - 1, i + 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActive((i) => Math.max(0, i - 1));
    } else if (e.key === 'Escape') {
      setOpen(false);
    }
  }

  return (
    <div className="sp-ac-wrap" ref={wrapRef} onMouseDown={() => { if (blurTimer.current) clearTimeout(blurTimer.current); }}>
      <input
        ref={inputRef}
        value={value || ''}
        maxLength={100}
        autoComplete="off"
        placeholder="Ex: Empresário, Médico, Consultor…"
        onChange={(e) => { onChange(e.target.value); sync(e.target.value); }}
        onFocus={() => sync(value)}
        onKeyDown={onKeyDown}
        onBlur={() => { blurTimer.current = setTimeout(() => setOpen(false), 120); }}
        role="combobox"
        aria-expanded={open}
        aria-autocomplete="list"
      />
      {open && items.length > 0 && (
        <div className="sp-ac-list" role="listbox" aria-label="Sugestões de profissão">
          {items.map((item, i) => (
            <button
              key={item}
              type="button"
              className={`sp-ac-option${i === active ? ' is-active' : ''}`}
              role="option"
              aria-selected={i === active}
              onMouseEnter={() => setActive(i)}
              onMouseDown={(e) => { e.preventDefault(); apply(item); }}
            >
              <span>{item}</span>
              {i === 0 && <small>Enter</small>}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
