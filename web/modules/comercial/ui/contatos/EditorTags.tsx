'use client';

// Tags da ficha (aba Dados): tira com o "×" e adiciona pelo campo (vírgula separa várias). Grava pela crm_tags_contato
// (migration 20261008222038): o banco normaliza (minúsculo, sem acento, hífen), confere dono/gestor (D6) e o máximo de 30.
import { useState } from 'react';
import { Button, Input } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { ComercialRepository, Resultado } from '../../application/ports';
import { MAX_TAGS_CONTATO, aplicarTags, tagsDoTexto } from '../../domain/tags';
import { Aviso } from '../comum';
import { avisarMudanca, repo } from '../repositorio';

/** Escrita fora do contrato comum (como `editarContato`): o Supabase grava; a demonstração não. */
type ComTags = ComercialRepository & {
  tagsContato?: (contatoId: string, adicionar: string[], remover: string[]) => Promise<Resultado & { tags?: string[] }>;
};

export function EditorTags({ contatoId, tags, onSalvo }: { contatoId: string; tags: string[]; onSalvo: (msg: string) => void }) {
  const [texto, setTexto] = useState('');
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const fonte = repo as ComTags;

  const gravar = async (adicionar: string[], remover: string[]) => {
    const previa = aplicarTags(tags, adicionar, remover);
    if (previa.erro) { setErro(previa.erro); return; }
    if (!fonte.tagsContato) { setErro('Demonstração: as tags só gravam no banco real.'); return; }
    setSalvando(true);
    setErro(null);
    const r = await fonte.tagsContato(contatoId, adicionar, remover);
    setSalvando(false);
    if (!r.ok) { setErro(r.msg ?? 'Não foi possível salvar as tags.'); return; }
    setTexto('');
    avisarMudanca();
    onSalvo(r.msg ?? 'Tags atualizadas.');
  };

  const novas = tagsDoTexto(texto);
  return (
    <div className="space-y-2">
      {tags.length ? (
        <ul className="flex flex-wrap gap-1.5" aria-label="Tags do contato">
          {tags.map((t) => (
            <li key={t} className="inline-flex items-center gap-1 rounded-[var(--r-pill)] border border-[var(--border)] bg-[var(--surface-3)] py-0.5 pl-2 pr-1 text-xs text-[var(--fg-2)]">
              <span className="max-w-[16rem] truncate">{t}</span>
              <button
                type="button"
                disabled={salvando}
                onClick={() => void gravar([], [t])}
                aria-label={`Remover a tag ${t}`}
                title="Remover tag"
                className="grid h-4 w-4 place-items-center rounded-[var(--r-pill)] text-[var(--fg-3)] hover:bg-[var(--surface-1)] hover:text-[var(--fg)] disabled:opacity-50"
              >
                <Icon name="x" size={11} />
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm text-[var(--fg-3)]">Sem tags.</p>
      )}
      {tags.length < MAX_TAGS_CONTATO && (
        <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); if (novas.length) void gravar(novas, []); }}>
          <Input
            value={texto}
            onChange={(e) => { setTexto(e.target.value); setErro(null); }}
            placeholder="Nova tag (vírgula separa várias)"
            aria-label="Nova tag"
            maxLength={300}
            autoComplete="off"
            className="flex-1"
          />
          <Button type="submit" size="sm" variant="ghost" disabled={salvando || novas.length === 0}>
            <Icon name="plus" size={13} /> Adicionar
          </Button>
        </form>
      )}
      {novas.length > 0 && <p className="text-[11px] text-[var(--fg-3)]">Vai gravar: {novas.join(', ')}</p>}
      {erro && <Aviso tom="danger" icone="alert" alerta>{erro}</Aviso>}
    </div>
  );
}
