'use client';

// Ficha do pedido de estratégia: o pedido, o público, o andamento e o placar (solicitante e gestor veem).
// Só o gestor comercial: mudar a situação e "Transformar em ação" (prévia + 1 clique).
import Link from 'next/link';
import { useState } from 'react';
import { Badge, Button, ConfirmDialog, Drawer, FilterSelect, Textarea } from '@/shared/ui/components';
import { fmtBRL, fmtData, fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import {
  LIMITE_FILA, LIMITE_FUNIL, ROTULO_PRIORIDADE, ROTULO_SITUACAO, ROTULO_TIPO_ACAO, TOM_SITUACAO, podeTransformar,
  proximasSituacoes, resumoFiltros, taxasPlacar,
  type Estrategia, type FiltrosPublico, type OpcoesFiltro, type PreviaPublico, type SituacaoEstrategia, type TipoAcao,
} from '../../domain/estrategias';
import type { ProdutoKey } from '../../domain/types';
import { Aviso, Campo, EsqueletoLista, EstadoErro, FaixaNumeros, Segmentado } from '../comum';
import { avisarMudanca, useDados } from '../repositorio';
import { EditorPublico } from './EditorPublico';
import { PreviaVista } from './PreviaPublico';
import { repoEstrategias } from './repositorio-estrategias';

const ROTULO_ACAO_SITUACAO: Partial<Record<SituacaoEstrategia, string>> = {
  em_analise: 'Colocar em análise',
  em_execucao: 'Marcar em execução',
  concluida: 'Concluir',
};

export function PedidoDrawer({ id, gestor, opcoes, onClose, flash }: {
  id: string; gestor: boolean; opcoes: OpcoesFiltro | null; onClose: () => void; flash: (m: string) => void;
}) {
  // Embrulhado: dados null = carregando; { e: null } = não existe ou a pessoa não vê.
  const { dados, erro, recarregar } = useDados(async () => ({ e: await repoEstrategias.pedido(id) }), [id]);
  const e = dados?.e ?? null;
  const [recusando, setRecusando] = useState(false);
  const [motivo, setMotivo] = useState('');
  const [msg, setMsg] = useState<string | null>(null);

  async function mudar(s: SituacaoEstrategia, nota?: string) {
    const r = await repoEstrategias.mudarSituacao(id, s, nota ?? null);
    if (!r.ok) { setMsg(r.msg ?? 'Não foi possível mudar.'); return; }
    setRecusando(false); setMotivo(''); setMsg(null);
    flash(`Situação: ${ROTULO_SITUACAO[s]}`);
    avisarMudanca();
  }

  const nomeProduto = (pid: string) => opcoes?.produtos.find((p) => p.id === pid)?.nome ?? pid;
  const linhaNome = (k: string | null) => (k ? opcoes?.linhas.find((l) => l.chave === k)?.nome ?? k.toUpperCase() : 'A definir');

  return (
    <Drawer
      onClose={onClose}
      title={e?.titulo ?? 'Pedido de estratégia'}
      subtitle={e ? `Pedido por ${e.solicitanteNome} em ${fmtData(e.criadoEm)}` : undefined}
      badges={e && (
        <>
          <Badge tone={TOM_SITUACAO[e.situacao]} dot>{ROTULO_SITUACAO[e.situacao]}</Badge>
          <Badge tone={e.prioridade === 'urgente' || e.prioridade === 'alta' ? 'warning' : 'neutral'}>Prioridade {ROTULO_PRIORIDADE[e.prioridade].toLowerCase()}</Badge>
          {e.prazo && <Badge>Prazo {fmtData(e.prazo)}</Badge>}
          {e.acaoTipo && <Badge tone="info">{ROTULO_TIPO_ACAO[e.acaoTipo]}</Badge>}
        </>
      )}
      footer={gestor && e && !recusando ? (
        <>
          {proximasSituacoes(e.situacao).filter((s) => s !== 'recusada' && ROTULO_ACAO_SITUACAO[s]).map((s) => (
            <Button key={s} size="sm" variant="subtle" onClick={() => mudar(s)}>{ROTULO_ACAO_SITUACAO[s]}</Button>
          ))}
          {proximasSituacoes(e.situacao).includes('recusada') && (
            <Button size="sm" variant="danger" onClick={() => setRecusando(true)}>Recusar</Button>
          )}
        </>
      ) : undefined}
    >
      {erro && !dados ? <EstadoErro mensagem={erro} onTentar={recarregar} />
        : !dados ? <EsqueletoLista linhas={4} avatar={false} />
          : !e ? <EstadoErro mensagem="Pedido não encontrado." />
            : (
              <div className="space-y-6">
                {msg && <Aviso tom="danger" icone="alert" titulo={msg} alerta />}
                {recusando && (
                  <div className="space-y-2 rounded-[var(--r-md)] border border-[var(--red-border)] p-3">
                    <Campo rotulo="Motivo da recusa" extra="obrigatório" dica="Quem pediu vai ver este motivo.">
                      <Textarea rows={2} autoFocus maxLength={500} value={motivo} onChange={(ev) => setMotivo(ev.target.value)} />
                    </Campo>
                    <div className="flex flex-wrap gap-2">
                      <Button size="sm" variant="ghost" onClick={() => { setRecusando(false); setMotivo(''); }}>Voltar</Button>
                      <Button size="sm" variant="danger" onClick={() => mudar('recusada', motivo)}>Recusar pedido</Button>
                    </div>
                  </div>
                )}

                {e.situacao === 'recusada' && e.motivoRecusa && (
                  <Aviso tom="danger" icone="x" titulo="Recusado pelo Comercial">{e.motivoRecusa}</Aviso>
                )}

                <Placar e={e} />

                <section className="space-y-2">
                  <h3 className="text-sm font-semibold text-[var(--fg)]">O pedido</h3>
                  <dl className="grid gap-x-6 gap-y-3 sm:grid-cols-2 text-sm">
                    <Item rotulo="Objetivo" valor={e.objetivo} largo />
                    {e.publico && <Item rotulo="Público" valor={e.publico} largo />}
                    <Item rotulo="Produto" valor={linhaNome(e.linha)} />
                    <Item rotulo="Oferta" valor={e.oferta ?? 'A definir'} />
                    <Item rotulo="Responsável no Comercial" valor={e.responsavelNome ?? 'Ainda ninguém'} />
                    {e.observacoes && <Item rotulo="Observações" valor={e.observacoes} largo />}
                  </dl>
                </section>

                {resumoFiltros(e.filtros, nomeProduto).length > 0 && (
                  <section className="space-y-2">
                    <h3 className="text-sm font-semibold text-[var(--fg)]">Público estruturado</h3>
                    <ul className="flex flex-wrap gap-1.5">
                      {resumoFiltros(e.filtros, nomeProduto).map((t) => <li key={t}><Badge>{t}</Badge></li>)}
                    </ul>
                  </section>
                )}

                {gestor && podeTransformar(e) && <PainelAcao e={e} opcoes={opcoes} flash={flash} />}

                <section className="space-y-2">
                  <h3 className="text-sm font-semibold text-[var(--fg)]">Andamento</h3>
                  <ol className="space-y-2">
                    {(e.historico ?? []).map((h, i) => (
                      <li key={i} className="flex gap-3 text-sm">
                        <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-[var(--accent)]" aria-hidden />
                        <span className="min-w-0">
                          <span className="font-medium text-[var(--fg)]">{ROTULO_SITUACAO[h.para]}</span>
                          <span className="text-[var(--fg-3)]"> · {fmtDataHora(h.em)}{h.porNome ? ` · ${h.porNome}` : ''}</span>
                          {h.nota && <span className="block text-[var(--fg-2)] break-words">{h.nota}</span>}
                        </span>
                      </li>
                    ))}
                  </ol>
                </section>
              </div>
            )}
    </Drawer>
  );
}

function Item({ rotulo, valor, largo = false }: { rotulo: string; valor: React.ReactNode; largo?: boolean }) {
  return (
    <div className={`min-w-0 ${largo ? 'sm:col-span-2' : ''}`}>
      <dt className="text-xs text-[var(--fg-3)]">{rotulo}</dt>
      <dd className="text-[var(--fg)] whitespace-pre-line break-words">{valor}</dd>
    </div>
  );
}

/** Placar da ação: o solicitante e o gestor veem o mesmo número. */
function Placar({ e }: { e: Estrategia }) {
  if (!e.acaoTipo || !e.placar) {
    return (
      <Aviso tom="neutral" icone="hourglass" titulo="Ainda sem ação">
        O placar aparece quando o Comercial transformar o pedido em ação.
      </Aviso>
    );
  }
  const p = e.placar;
  const t = taxasPlacar(p);
  return (
    <section className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-sm font-semibold text-[var(--fg)]">Placar</h3>
        <span className="text-xs text-[var(--fg-3)]">
          {ROTULO_TIPO_ACAO[e.acaoTipo]} desde {fmtData(e.acaoCriadaEm)}
          {e.acaoTipo === 'funil' && e.funilId && <> · <Link className="text-[var(--accent)] hover:underline" href={`/comercial/funil?f=${e.funilId}`}>abrir funil</Link></>}
          {e.acaoTipo === 'fila' && <> · <Link className="text-[var(--accent)] hover:underline" href="/comercial/estrategias#filas">abrir filas</Link></>}
        </span>
      </div>
      <FaixaNumeros
        rotulo="Placar da ação"
        itens={[
          { rotulo: 'Na lista', valor: p.naLista.toLocaleString('pt-BR') },
          { rotulo: 'Abordadas', valor: `${p.abordadas.toLocaleString('pt-BR')} (${t.abordagem.toLocaleString('pt-BR')}%)` },
          { rotulo: 'Em conversa', valor: p.emConversa.toLocaleString('pt-BR') },
          { rotulo: 'Vendas', valor: `${p.vendas.toLocaleString('pt-BR')} (${t.conversao.toLocaleString('pt-BR')}%)` },
          { rotulo: 'Receita', valor: fmtBRL(p.receita) },
        ]}
      />
    </section>
  );
}

/** "Transformar em ação": tipo, produto, ajuste do público, prévia e 1 clique. */
function PainelAcao({ e, opcoes, flash }: { e: Estrategia; opcoes: OpcoesFiltro | null; flash: (m: string) => void }) {
  const [tipo, setTipo] = useState<TipoAcao>('fila');
  const [linha, setLinha] = useState<ProdutoKey | ''>(e.linha ?? '');
  const [filtros, setFiltros] = useState<FiltrosPublico>(structuredClone(e.filtros));
  const [editar, setEditar] = useState(Object.keys(e.filtros).length === 0);
  const [previa, setPrevia] = useState<PreviaPublico | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [confirmar, setConfirmar] = useState(false);

  async function verPrevia() {
    setOcupado(true); setErro(null);
    const r = await repoEstrategias.previa(filtros);
    setOcupado(false);
    if (!r.ok || !r.previa) { setErro(r.msg ?? 'Não foi possível calcular o público.'); setPrevia(null); return; }
    setPrevia(r.previa);
  }

  async function criar() {
    setConfirmar(false); setOcupado(true); setErro(null);
    const r = await repoEstrategias.transformar(e.id, tipo, linha || null, filtros);
    setOcupado(false);
    if (!r.ok) { setErro(r.msg ?? 'Não foi possível criar a ação.'); return; }
    flash(r.msg ?? 'Ação criada.');
    avisarMudanca();
  }

  const limite = tipo === 'fila' ? LIMITE_FILA : LIMITE_FUNIL;
  const acima = !!previa && previa.total > limite;
  return (
    <section className="space-y-3 rounded-[var(--r-md)] border border-[var(--border-accent)] bg-[var(--surface-2)] p-4">
      <div>
        <h3 className="text-sm font-semibold text-[var(--fg)]">Transformar em ação</h3>
        <p className="text-xs text-[var(--fg-3)]">
          As pessoas vão para os vendedores pela distribuição. Quem já tem dono fica com o mesmo dono.
        </p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="min-w-0">
          <span className="mb-1 block text-xs font-medium text-[var(--fg-2)]">Tipo de ação</span>
          <Segmentado rotulo="Tipo de ação" valor={tipo} onChange={setTipo} opcoes={[
            { valor: 'fila', rotulo: 'Fila de recuperação', title: `Até ${LIMITE_FILA.toLocaleString('pt-BR')} pessoas` },
            { valor: 'funil', rotulo: 'Funil próprio', title: `Até ${LIMITE_FUNIL} pessoas, cada uma vira um negócio` },
          ]} />
        </div>
        <Campo rotulo="Produto da ação" extra="obrigatório">
          <FilterSelect value={linha} onChange={(ev) => setLinha(ev.target.value as ProdutoKey | '')} className="w-full">
            <option value="">Escolha</option>
            {(opcoes?.linhas ?? []).map((l) => <option key={l.chave} value={l.chave}>{l.nome} (escada {l.escada})</option>)}
          </FilterSelect>
        </Campo>
      </div>
      <div className="flex flex-wrap gap-2">
        <Button size="sm" variant="ghost" aria-expanded={editar} onClick={() => setEditar((v) => !v)}>
          <Icon name={editar ? 'chevron-up' : 'chevron-down'} size={14} /> Ajustar público
        </Button>
        <Button size="sm" variant="subtle" onClick={verPrevia} disabled={ocupado}><Icon name="users" size={14} /> Ver prévia</Button>
      </div>
      {editar && <EditorPublico valor={filtros} onChange={(f) => { setFiltros(f); setPrevia(null); }} opcoes={opcoes} />}
      {previa && <PreviaVista previa={previa} />}
      {acima && <Aviso tom="warning" titulo={`Mais de ${limite.toLocaleString('pt-BR')} pessoas para ${tipo === 'fila' ? 'a fila' : 'o funil'}.`}>Refine o público{tipo === 'funil' ? ' ou use a fila de recuperação' : ''}.</Aviso>}
      {erro && <Aviso tom="danger" icone="alert" titulo={erro} alerta />}
      <Button onClick={() => setConfirmar(true)} disabled={ocupado || !previa || previa.total === 0 || acima || !linha}>
        <Icon name="zap" size={14} /> Criar {tipo === 'fila' ? 'fila' : 'funil'} com {previa ? previa.total.toLocaleString('pt-BR') : '…'} pessoa(s)
      </Button>
      {!previa && <p className="text-xs text-[var(--fg-3)]">Veja a prévia antes de criar.</p>}
      <ConfirmDialog
        open={confirmar}
        title="Criar a ação?"
        message={`${ROTULO_TIPO_ACAO[tipo]} com ${previa?.total.toLocaleString('pt-BR') ?? 0} pessoa(s). Os vendedores recebem um aviso com o total da carteira.`}
        confirmLabel="Criar ação"
        onConfirm={criar}
        onCancel={() => setConfirmar(false)}
      />
    </section>
  );
}
