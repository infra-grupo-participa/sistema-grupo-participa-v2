// Markdown mínimo e seguro (só elementos React, nada de innerHTML) para o playbook dentro do app.
// Cobre o que o playbook usa: títulos, parágrafos, listas, tabelas, citação, bloco de código, régua, **negrito** e `código`.
import { Fragment } from 'react';

function inline(t: string, k: string): React.ReactNode[] {
  const out: React.ReactNode[] = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`)/g;
  let i = 0;
  let m: RegExpExecArray | null;
  let n = 0;
  while ((m = re.exec(t))) {
    if (m.index > i) out.push(t.slice(i, m.index));
    const s = m[0];
    out.push(s.startsWith('**')
      ? <strong key={`${k}-${n++}`} className="font-semibold text-[var(--fg)]">{s.slice(2, -2)}</strong>
      : <code key={`${k}-${n++}`} className="rounded bg-[var(--surface-3)] px-1 py-0.5 text-[0.85em]">{s.slice(1, -1)}</code>);
    i = m.index + s.length;
  }
  if (i < t.length) out.push(t.slice(i));
  return out;
}

const celulas = (l: string) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());

export function Markdown({ texto }: { texto: string }) {
  const linhas = texto.split('\n');
  const blocos: React.ReactNode[] = [];
  let i = 0;
  let k = 0;
  while (i < linhas.length) {
    const l = linhas[i];
    const key = `b${k++}`;
    if (!l.trim()) { i++; continue; }
    if (l.startsWith('```')) {
      const corpo: string[] = [];
      i++;
      while (i < linhas.length && !linhas[i].startsWith('```')) corpo.push(linhas[i++]);
      i++;
      blocos.push(<pre key={key} className="my-3 overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3 text-xs leading-relaxed text-[var(--fg-2)]">{corpo.join('\n')}</pre>);
      continue;
    }
    if (/^---+$/.test(l.trim())) { blocos.push(<hr key={key} className="my-6 border-[var(--border)]" />); i++; continue; }
    const h = /^(#{1,4})\s+(.*)$/.exec(l);
    if (h) {
      const n = h[1].length;
      const cls = n === 1 ? 'text-2xl font-bold mt-2' : n === 2 ? 'text-xl font-bold mt-8' : 'text-base font-semibold mt-6';
      const Tag = (`h${Math.min(n + 1, 4)}`) as 'h2' | 'h3' | 'h4';
      blocos.push(<Tag key={key} className={`${cls} text-[var(--fg)]`}>{inline(h[2], key)}</Tag>);
      i++;
      continue;
    }
    if (l.trim().startsWith('|')) {
      const tab: string[] = [];
      while (i < linhas.length && linhas[i].trim().startsWith('|')) tab.push(linhas[i++]);
      const [cab, , ...corpo] = tab;
      blocos.push(
        <div key={key} className="my-3 overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
          <table className="w-full text-sm">
            <thead className="bg-[var(--surface-2)]"><tr>{celulas(cab).map((c, j) => <th key={j} className="px-3 py-2 text-left font-semibold text-[var(--fg)]">{inline(c, `${key}h${j}`)}</th>)}</tr></thead>
            <tbody>{corpo.map((r, ri) => <tr key={ri} className="border-t border-[var(--border)]">{celulas(r).map((c, j) => <td key={j} className="px-3 py-2 align-top text-[var(--fg-2)]">{inline(c, `${key}c${ri}${j}`)}</td>)}</tr>)}</tbody>
          </table>
        </div>,
      );
      continue;
    }
    if (l.startsWith('>')) {
      const q: string[] = [];
      while (i < linhas.length && linhas[i].startsWith('>')) q.push(linhas[i++].replace(/^>\s?/, ''));
      blocos.push(<blockquote key={key} className="my-3 border-l-2 border-[var(--accent)] bg-[var(--accent-subtle)] px-4 py-2 text-sm text-[var(--fg)]">{inline(q.join(' '), key)}</blockquote>);
      continue;
    }
    if (/^\s*([-*]|\d+\.)\s+/.test(l)) {
      const numerada = /^\s*\d+\./.test(l);
      const itens: string[] = [];
      while (i < linhas.length && /^\s*([-*]|\d+\.)\s+/.test(linhas[i])) itens.push(linhas[i++].replace(/^\s*([-*]|\d+\.)\s+/, ''));
      const L = numerada ? 'ol' : 'ul';
      blocos.push(<L key={key} className={`my-2 space-y-1 pl-5 text-sm text-[var(--fg-2)] ${numerada ? 'list-decimal' : 'list-disc'}`}>{itens.map((t, j) => <li key={j}>{inline(t, `${key}${j}`)}</li>)}</L>);
      continue;
    }
    const par: string[] = [];
    while (i < linhas.length && linhas[i].trim() && !/^(#|\||>|```|---|\s*([-*]|\d+\.)\s)/.test(linhas[i])) par.push(linhas[i++]);
    blocos.push(<p key={key} className="my-2 text-sm leading-relaxed text-[var(--fg-2)]">{inline(par.join(' '), key)}</p>);
  }
  return <Fragment>{blocos}</Fragment>;
}
