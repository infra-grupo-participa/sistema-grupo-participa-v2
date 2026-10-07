'use client';

// Nova solicitação de estratégia (quem tem a função comercial.solicitar_estrategia). O público pode ser só texto;
// os filtros estruturados e o modelo pronto são opcionais e mostram a contagem antes de enviar.
import { useState } from 'react';
import { Button, FilterSelect, Input, Modal, Textarea } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  ROTULO_PRIORIDADE, filtrosVazios, validarSolicitacao,
  type FiltrosPublico, type ModeloPublico, type NovaSolicitacao, type OpcoesFiltro, type PreviaPublico, type PrioridadeEstrategia,
} from '../../domain/estrategias';
import type { ProdutoKey } from '../../domain/types';
import { Aviso, Campo } from '../comum';
import { EditorPublico } from './EditorPublico';
import { contarFiltros } from './editor';
import { PreviaVista } from './PreviaPublico';
import { repoEstrategias } from './repositorio-estrategias';

const VAZIO: NovaSolicitacao = {
  titulo: '', objetivo: '', publico: '', filtros: {}, modelo: null, linha: null, oferta: '', prazo: null, prioridade: 'media', observacoes: '',
};

export function ModalSolicitacao({ modelos, opcoes, onClose, onSalvo }: {
  modelos: ModeloPublico[]; opcoes: OpcoesFiltro | null; onClose: () => void; onSalvo: (id: string, msg: string) => void;
}) {
  const [s, setS] = useState<NovaSolicitacao>(VAZIO);
  const [verFiltros, setVerFiltros] = useState(false);
  const [previa, setPrevia] = useState<PreviaPublico | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const set = (p: Partial<NovaSolicitacao>) => { setS((x) => ({ ...x, ...p })); setErro(null); };
  const setFiltros = (f: FiltrosPublico) => { set({ filtros: f }); setPrevia(null); };

  function escolherModelo(chave: string) {
    const m = modelos.find((x) => x.chave === chave) ?? null;
    set({ modelo: m?.chave ?? null, filtros: m ? structuredClone(m.filtros) : {}, publico: s.publico || (m?.descricao ?? '') });
    setPrevia(null);
    if (m) setVerFiltros(true);
  }

  async function contar() {
    setOcupado(true);
    const r = await repoEstrategias.previa(s.filtros);
    setOcupado(false);
    if (!r.ok || !r.previa) { setErro(r.msg ?? 'Não foi possível contar o público.'); return; }
    setPrevia(r.previa);
  }

  async function enviar() {
    const msg = validarSolicitacao(s, new Date());
    if (msg) { setErro(msg); return; }
    setOcupado(true);
    const r = await repoEstrategias.salvar(s);
    setOcupado(false);
    if (!r.ok || !r.id) { setErro(r.msg ?? 'Não foi possível enviar.'); return; }
    onSalvo(r.id, r.msg ?? 'Pedido enviado ao Comercial.');
  }

  const nFiltros = contarFiltros(s.filtros);
  return (
    <Modal
      onClose={onClose}
      title="Nova solicitação de estratégia"
      width="max-w-2xl"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>Cancelar</Button>
          <Button onClick={enviar} disabled={ocupado}><Icon name="send" size={14} /> Enviar ao Comercial</Button>
        </>
      }
    >
      <div className="space-y-4">
        <Campo rotulo="Título" extra="obrigatório">
          <Input autoFocus maxLength={120} value={s.titulo} onChange={(e) => set({ titulo: e.target.value })} placeholder="Ex.: Própria holding: alunos do THB" />
        </Campo>
        <Campo rotulo="Objetivo" extra="obrigatório">
          <Textarea rows={3} maxLength={2000} value={s.objetivo} onChange={(e) => set({ objetivo: e.target.value })}
            placeholder="O que o Comercial deve conseguir com esta ação." />
        </Campo>
        <Campo rotulo="Público" dica="Com suas palavras. Os filtros abaixo são opcionais.">
          <Textarea rows={2} maxLength={2000} value={s.publico} onChange={(e) => set({ publico: e.target.value })}
            placeholder="Ex.: alunos que disseram nas pesquisas que querem fazer a própria holding" />
        </Campo>

        <div className="grid gap-3 sm:grid-cols-2">
          <Campo rotulo="Produto ou oferta (linha)">
            <FilterSelect value={s.linha ?? ''} onChange={(e) => set({ linha: (e.target.value || null) as ProdutoKey | null })} className="w-full">
              <option value="">A definir</option>
              {(opcoes?.linhas ?? []).map((l) => <option key={l.chave} value={l.chave}>{l.nome} (escada {l.escada})</option>)}
            </FilterSelect>
          </Campo>
          <Campo rotulo="Oferta" dica="Opcional. Ex.: condição especial do lote.">
            <Input maxLength={200} value={s.oferta} onChange={(e) => set({ oferta: e.target.value })} />
          </Campo>
          <Campo rotulo="Prazo">
            <Input type="date" value={s.prazo ?? ''} onChange={(e) => set({ prazo: e.target.value || null })} />
          </Campo>
          <Campo rotulo="Prioridade">
            <FilterSelect value={s.prioridade} onChange={(e) => set({ prioridade: e.target.value as PrioridadeEstrategia })} className="w-full">
              {(Object.keys(ROTULO_PRIORIDADE) as PrioridadeEstrategia[]).map((p) => <option key={p} value={p}>{ROTULO_PRIORIDADE[p]}</option>)}
            </FilterSelect>
          </Campo>
        </div>

        <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3 space-y-3">
          <Campo rotulo="Modelo de público pronto">
            <FilterSelect value={s.modelo ?? ''} onChange={(e) => escolherModelo(e.target.value)} className="w-full">
              <option value="">Nenhum</option>
              {modelos.map((m) => <option key={m.chave} value={m.chave}>{m.nome}</option>)}
            </FilterSelect>
          </Campo>
          <div className="flex flex-wrap items-center gap-2">
            <Button type="button" size="sm" variant="ghost" aria-expanded={verFiltros} onClick={() => setVerFiltros((v) => !v)}>
              <Icon name={verFiltros ? 'chevron-up' : 'chevron-down'} size={14} /> Filtros estruturados{nFiltros ? ` (${nFiltros})` : ''}
            </Button>
            {!filtrosVazios(s.filtros) && (
              <Button type="button" size="sm" variant="subtle" onClick={contar} disabled={ocupado}>
                <Icon name="users" size={14} /> Contar público
              </Button>
            )}
          </div>
          {verFiltros && <EditorPublico valor={s.filtros} onChange={setFiltros} opcoes={opcoes} />}
          {previa && <PreviaVista previa={previa} />}
        </div>

        <Campo rotulo="Observações">
          <Textarea rows={2} maxLength={2000} value={s.observacoes} onChange={(e) => set({ observacoes: e.target.value })} />
        </Campo>

        {erro && <Aviso tom="danger" icone="alert" titulo={erro} alerta />}
      </div>
    </Modal>
  );
}
