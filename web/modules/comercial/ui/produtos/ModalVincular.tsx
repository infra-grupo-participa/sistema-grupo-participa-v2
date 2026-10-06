'use client';

// Vincular um produto da Hotmart ao comercial (ou editar o vínculo). Não cria produto: só diz como o
// comercial chama, em que agrupador mora e de que escada é.
import { useState } from 'react';
import { Button, FilterSelect, Input, Modal } from '@/shared/ui/components';
import { PRODUTOS } from '../../domain/catalogo';
import type { Agrupador, Escada, ProdutoHotmart, ProdutoKey } from '../../domain/types';
import { Campo, Chip } from '../comum';
import { avisarMudanca, repo } from '../repositorio';
import { LIMITE_NOME_COMERCIAL, ROTULO_CONTA, rascunhoVinculo, validarVinculo } from './produtos';

export function ModalVincular({ produto: p, agrupadores, onFechar, flash }: {
  produto: ProdutoHotmart; agrupadores: Agrupador[]; onFechar: () => void; flash: (m: string) => void;
}) {
  const [r, setR] = useState(() => rascunhoVinculo(p));
  const [tentou, setTentou] = useState(false);
  const [salvando, setSalvando] = useState(false);
  const erros = validarVinculo(r);

  // Escolher o produto do CRM sugere a escada dele (o gestor pode trocar).
  function trocarProdutoKey(v: string) {
    const k = (v || null) as ProdutoKey | null;
    const escada = k ? PRODUTOS.find((x) => x.key === k)?.escada ?? r.escada : r.escada;
    const ag = k && !r.agrupadorId ? agrupadores.find((a) => a.produto === k)?.id ?? null : r.agrupadorId;
    setR({ ...r, produtoKey: k, escada, agrupadorId: ag });
  }

  async function salvar() {
    setTentou(true);
    if (Object.keys(erros).length) return;
    setSalvando(true);
    const res = await repo.vincularProduto({
      produtoId: p.produtoId, noComercial: true, nomeComercial: r.nomeComercial.trim(), produtoKey: r.produtoKey, agrupadorId: r.agrupadorId, escada: r.escada,
    });
    setSalvando(false);
    flash(res.msg ?? (res.ok ? 'Produto vinculado.' : 'Não foi possível salvar.'));
    if (res.ok) { avisarMudanca(); onFechar(); }
  }

  return (
    <Modal
      onClose={onFechar}
      title={p.noComercial ? 'Editar vínculo' : 'Vincular ao comercial'}
      footer={
        <>
          <Button size="sm" variant="ghost" onClick={onFechar}>Cancelar</Button>
          <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : p.noComercial ? 'Salvar vínculo' : 'Vincular'}</Button>
        </>
      }
    >
      <div className="space-y-4">
        <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2 text-xs text-[var(--fg-3)]">
          <span className="block text-sm font-medium text-[var(--fg)]">{p.nomeHotmart}</span>
          Id {p.produtoId} · {ROTULO_CONTA[p.conta]}{p.familia ? ` · ${p.familia}` : ''} · veio da Hotmart
        </div>

        <Campo rotulo="Nome comercial" extra="obrigatório" dica="Como o time chama o produto no funil e nos relatórios.">
          <Input
            value={r.nomeComercial}
            onChange={(e) => setR({ ...r, nomeComercial: e.target.value })}
            maxLength={LIMITE_NOME_COMERCIAL}
            placeholder="Ex.: Holding Masters"
            aria-invalid={tentou && !!erros.nomeComercial}
            autoFocus
          />
        </Campo>
        {tentou && erros.nomeComercial && <p role="alert" className="-mt-3 text-xs text-[var(--red)]">{erros.nomeComercial}</p>}

        <div className="grid gap-3 sm:grid-cols-2">
          <Campo rotulo="Produto do CRM" dica="Liga aos funis de venda ativa do produto.">
            <FilterSelect value={r.produtoKey ?? ''} onChange={(e) => trocarProdutoKey(e.target.value)} className="w-full">
              <option value="">Nenhum</option>
              {PRODUTOS.map((x) => <option key={x.key} value={x.key}>{x.nome}</option>)}
            </FilterSelect>
          </Campo>
          <Campo rotulo="Agrupador" dica="Pasta de funis onde o produto aparece.">
            <FilterSelect value={r.agrupadorId ?? ''} onChange={(e) => setR({ ...r, agrupadorId: e.target.value || null })} className="w-full">
              <option value="">Nenhum</option>
              {agrupadores.map((a) => <option key={a.id} value={a.id}>{a.nome}</option>)}
            </FilterSelect>
          </Campo>
        </div>

        <div>
          <span className="mb-1 flex items-center justify-between text-xs font-medium text-[var(--fg-2)]">
            <span>Escada</span><span className="text-[11px] font-normal">obrigatória</span>
          </span>
          {/* Sem escada marcada até o gestor escolher (Segmentado sempre marca uma). */}
          <div role="group" aria-label="Escada do produto" className="flex flex-wrap gap-2">
            {(['A', 'B'] as Escada[]).map((e) => (
              <Chip key={e} ativo={r.escada === e} onClick={() => setR({ ...r, escada: e })} icone={e === 'A' ? 'briefcase' : 'graduation'}>
                {e === 'A' ? 'A · serviço do escritório' : 'B · infoproduto'}
              </Chip>
            ))}
          </div>
          <span className="mt-1 block text-[11px] text-[var(--fg-3)]">A = cliente final (serviço). B = profissional (formação). Nunca misturar.</span>
          {tentou && erros.escada && <p role="alert" className="mt-1 text-xs text-[var(--red)]">{erros.escada}</p>}
        </div>
      </div>
    </Modal>
  );
}
