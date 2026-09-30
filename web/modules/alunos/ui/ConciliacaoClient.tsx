'use client';

// Área "Conciliação" da Base de Alunos + a carga que alimenta a área E a ficha.
// Carga: fn_aluno_conciliacao_lista(true) 1× por abertura da página, em segundo plano (useConciliacao fica em
// AlunosClient, que não desmonta). Resumo, filtro, "Mostrar conferidos" e paginação saem dessas linhas, no
// cliente: trocar de aba ou de filtro não chama o banco. Marcar/desfazer mudam o estado local na hora e voltam
// atrás se o banco recusar; só "Tentar de novo", edição do aluno e "Definir titular" recarregam (1×).
// "Ver dados" = 1 chamada por clique, guardada só enquanto a linha está aberta.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Badge, Button, Checkbox, DataTable, EmptyState, MultiSelect, Td, Th, Thead, Toolbar, Tr } from '@/shared/ui/components';
import { fmtData } from '@/shared/ui/format';
import type { Aluno360 } from '../domain/aluno-360';
import {
  GRUPOS, ROTULO_DECISAO, SEVERIDADES, abaDoItem, aplicarDecisao, contar, decisoesDoTipo, indexarPorAluno, ordenarItens, resumoDetalhe,
  rotuloAcao, rotuloGrupo, rotuloSeveridade, rotuloTipo, umaLinhaPorItem,
  type DecisaoConciliacao, type ItemConciliacao,
} from '../domain/conciliacao';
import { rotuloMotivo } from '../domain/programa-selo';
import { montarHashFicha, type AbaFicha } from '../domain/ficha-aluno-abas';
import { desmarcarConciliacao, loadConciliacao, loadConciliacaoRef, marcarConciliacao, type Resultado } from './conciliacao-data';

export interface DadosConciliacao {
  /** Todas as linhas, abertas E conferidas. Quem quer só as abertas filtra por `conferido`. */
  itens: ItemConciliacao[] | null;
  erro: string | null;
  /** Só itens em aberto. */
  porAluno: Map<string, ItemConciliacao[]>;
  recarregar: () => void;
  /** 1 RPC; o estado local muda antes e volta atrás se o banco recusar. */
  marcar: (item: string, decisao: DecisaoConciliacao, obs: string) => Promise<Resultado<number | null>>;
  /** 1 RPC; idem. */
  desmarcar: (item: string, decisaoId: number) => Promise<Resultado<null>>;
}

/** 1 chamada quando `ativo` vira true; `recarregar` repete (após mudança que o cliente não sabe refazer). */
export function useConciliacao(ativo: boolean): DadosConciliacao {
  const [itens, setItens] = useState<ItemConciliacao[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [versao, setVersao] = useState(0);
  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    loadConciliacao(true).then((r) => {
      if (!vivo) return;
      if (r.ok) { setItens(r.data); setErro(null); } else setErro(r.erro);
    });
    return () => { vivo = false; };
  }, [ativo, versao]);
  const porAluno = useMemo(() => indexarPorAluno(itens ?? []), [itens]);
  const recarregar = useCallback(() => setVersao((v) => v + 1), []);
  const aplicar = useCallback((item: string, conferido: boolean, id: number | null) =>
    setItens((cur) => (cur ? aplicarDecisao(cur, item, conferido, id) : cur)), []);
  const marcar = useCallback(async (item: string, decisao: DecisaoConciliacao, obs: string) => {
    aplicar(item, true, null);
    const r = await marcarConciliacao(item, decisao, obs);
    if (r.ok) aplicar(item, true, r.data); else aplicar(item, false, null);
    return r;
  }, [aplicar]);
  const desmarcar = useCallback(async (item: string, decisaoId: number) => {
    aplicar(item, false, null);
    const r = await desmarcarConciliacao(decisaoId);
    if (!r.ok) aplicar(item, true, decisaoId);
    return r;
  }, [aplicar]);
  return { itens, erro, porAluno, recarregar, marcar, desmarcar };
}

const TOM_SEV: Record<string, 'danger' | 'warning' | 'neutral' | 'info'> = { alta: 'danger', media: 'warning', baixa: 'neutral', info: 'info' };
const POR_PAGINA = 100;

export function ConciliacaoClient({ dados, alunos, canEdit, onAbrirAluno, onMudou }: {
  dados: DadosConciliacao;
  alunos: Aluno360[];
  canEdit: boolean;
  onAbrirAluno: (id: string, aba: AbaFicha) => void;
  /** Depois de marcar/desfazer: quem chama só avisa (o estado já foi atualizado em `dados`). */
  onMudou: (msg: string) => void;
}) {
  const [grupo, setGrupo] = useState<string | null>(null);
  const [tipo, setTipo] = useState<string | null>(null);
  const [sev, setSev] = useState<string[]>(['alta']);
  const [comConferidos, setComConferidos] = useState(false);
  const [pagina, setPaginaDe] = useState<{ recorte: string; n: number }>({ recorte: '', n: 0 });
  const [aberta, setAberta] = useState<{ item: string; modo: 'marcar' | 'ver' } | null>(null);
  const [ultimo, setUltimo] = useState<{ item: string; id: number } | null>(null);
  const desfazendo = useRef(false);

  const base = dados.itens;
  const erro = dados.erro;
  const nomePorId = useMemo(() => new Map(alunos.map((a) => [a.id, a.nome])), [alunos]);

  // Contagem por severidade sobre a base toda; por grupo/tipo sobre o recorte de severidade. Aberto e conferido
  // contam separados; a lista mostra conferido só com a caixa marcada.
  const contSev = useMemo(() => contar(base ?? []).severidade, [base]);
  const porSev = useMemo(() => (base ?? []).filter((i) => !sev.length || sev.includes(i.severidade)), [base, sev]);
  const cont = useMemo(() => contar(porSev), [porSev]);
  const linhas = useMemo(() => ordenarItens(umaLinhaPorItem(porSev.filter((i) =>
    (comConferidos || !i.conferido) && (!grupo || i.grupo === grupo) && (!tipo || i.tipo === tipo)))), [porSev, comConferidos, grupo, tipo]);
  const tiposDoGrupo = useMemo(() => (grupo ? Object.keys(cont.tipo).filter((t) => porSev.some((i) => i.tipo === t && i.grupo === grupo)) : []), [grupo, cont, porSev]);
  const nPaginas = Math.max(1, Math.ceil(linhas.length / POR_PAGINA));
  // A página vale só para o recorte em que foi escolhida: mudou filtro, volta à 1ª (sem efeito, sem render extra).
  const recorte = `${sev.join(',')}|${comConferidos}|${grupo ?? ''}|${tipo ?? ''}`;
  const pag = Math.min(pagina.recorte === recorte ? pagina.n : 0, nPaginas - 1);
  const setPagina = (n: number) => setPaginaDe({ recorte, n });

  if (erro) {
    return (
      <div className="flex flex-wrap items-center gap-2" role="alert">
        <p className="text-sm text-[var(--fg-3)]">Conciliação indisponível no momento. {erro}</p>
        <Button size="sm" variant="ghost" onClick={dados.recarregar}>Tentar de novo</Button>
      </div>
    );
  }
  if (!base) return <p className="text-sm text-[var(--fg-3)]" role="status">Carregando conciliação…</p>;

  const link = (id: string | null, aba: AbaFicha) => {
    if (!id) return null;
    const nome = nomePorId.get(id);
    if (nome === undefined) return <span className="text-xs text-[var(--fg-3)]">fora da Central de Acessos</span>;
    return (
      <a
        href={montarHashFicha(id, aba)}
        onClick={(e) => { e.preventDefault(); onAbrirAluno(id, aba); }}
        className="text-[var(--accent)] hover:underline focus-visible:ring-2 rounded-[var(--r-sm)]"
      >
        {nome || 'Sem nome'}
      </a>
    );
  };

  const botaoFiltro = (ativo: boolean, onClick: () => void, rotulo: string, n: number, conferidos: number, ariaExtra: string) => (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={ativo}
      aria-label={`${rotulo}: ${n} ${n === 1 ? 'item' : 'itens'} em aberto${ariaExtra}${conferidos ? `, ${conferidos} conferidos` : ''}`}
      className={`px-3 py-1.5 text-left border rounded-[var(--r-md)] focus-visible:ring-2 ${ativo ? 'border-[var(--border-accent)] bg-[var(--surface-3)]' : 'border-[var(--border)] hover:bg-[var(--surface-2)]'}`}
    >
      <div className="text-[10px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</div>
      <div className="text-sm font-semibold text-[var(--fg)] tabular">
        {n.toLocaleString('pt-BR')}
        {conferidos > 0 && <span className="ml-1.5 text-[11px] font-normal text-[var(--fg-3)]">+{conferidos.toLocaleString('pt-BR')} conf.</span>}
      </div>
    </button>
  );

  // Otimista: a linha sai da lista na hora (o form fecha junto); se o banco recusar, ela volta e o aviso sobe.
  const confirmarMarca = async (item: string, decisao: DecisaoConciliacao, obs: string) => {
    setAberta(null);
    const r = await dados.marcar(item, decisao, obs);
    if (!r.ok) { onMudou(r.erro); return; }
    if (r.data != null) setUltimo({ item, id: r.data });
    onMudou('Item marcado como conferido.');
  };

  const desfazer = async () => {
    if (!ultimo || desfazendo.current) return;
    desfazendo.current = true;
    const alvo = ultimo;
    setUltimo(null);
    const r = await dados.desmarcar(alvo.item, alvo.id);
    desfazendo.current = false;
    if (r.ok) onMudou('Marcação desfeita.'); else { setUltimo(alvo); onMudou(r.erro); }
  };

  return (
    <div>
      <div className="flex flex-wrap gap-2 mb-3" aria-label="Contagem por grupo">
        {GRUPOS.filter((g) => cont.grupo[g]).map((g) => botaoFiltro(
          grupo === g,
          () => { setGrupo(grupo === g ? null : g); setTipo(null); },
          rotuloGrupo(g), cont.grupo[g].itens, cont.grupo[g].conferidos, `, ${cont.grupo[g].alunos} alunos`,
        ))}
      </div>
      {tiposDoGrupo.length > 1 && (
        <div className="flex flex-wrap gap-2 mb-3" aria-label="Contagem por tipo">
          {tiposDoGrupo.map((t) => botaoFiltro(tipo === t, () => setTipo(tipo === t ? null : t), rotuloTipo(t), cont.tipo[t].itens, cont.tipo[t].conferidos, ''))}
        </div>
      )}

      <Toolbar className="mb-2">
        <MultiSelect values={sev} onChange={setSev} placeholder="Todas as severidades" options={SEVERIDADES.map((s) => ({ value: s, label: `${rotuloSeveridade(s)} (${(contSev[s]?.itens ?? 0).toLocaleString('pt-BR')})` }))} />
        <Checkbox checked={comConferidos} onChange={setComConferidos} label="Mostrar conferidos" />
        <span className="text-xs text-[var(--fg-3)] tabular" role="status">{linhas.length.toLocaleString('pt-BR')} {linhas.length === 1 ? 'item' : 'itens'}</span>
        {ultimo && <Button size="sm" variant="ghost" onClick={desfazer}>Desfazer a última marcação</Button>}
      </Toolbar>

      <DataTable>
        <Thead>
          <Th>Severidade</Th>
          <Th>Pendência</Th>
          <Th>Aluno</Th>
          <Th>Outro cadastro</Th>
          <Th>O que fazer</Th>
          {canEdit && <Th><span className="sr-only">Ações</span></Th>}
        </Thead>
        <tbody>
          {linhas.slice(pag * POR_PAGINA, (pag + 1) * POR_PAGINA).map((it) => {
            const aba = abaDoItem(it);
            const det = resumoDetalhe(it, rotuloMotivo);
            const expandida = aberta?.item === it.item ? aberta.modo : null;
            return [
              <Tr key={it.item}>
                <Td><Badge tone={TOM_SEV[it.severidade] ?? 'neutral'}>{rotuloSeveridade(it.severidade)}</Badge></Td>
                <Td>
                  <div className="text-[var(--fg)]">{rotuloTipo(it.tipo)}</div>
                  {det && <div className="text-[11px] text-[var(--fg-3)] mt-0.5">{det}</div>}
                  {it.conferido && <div className="text-[11px] text-[var(--green)] mt-0.5">Conferido</div>}
                </Td>
                <Td>
                  {/* "Ver dados" chama fn_aluno_conciliacao_ref, que o banco nega a quem só visualiza (20261003i M1). */}
                  {it.aluno_id ? link(it.aluno_id, aba) : !canEdit ? <span className="text-[var(--fg-3)]">Fora da base</span> : (
                    <Button size="sm" variant="link" aria-expanded={expandida === 'ver'} onClick={() => setAberta(expandida === 'ver' ? null : { item: it.item, modo: 'ver' })}>
                      Ver dados
                    </Button>
                  )}
                </Td>
                <Td>{link(it.ref_aluno_id, aba) ?? <span className="text-[var(--fg-3)]">—</span>}</Td>
                <Td className="text-[var(--fg-2)]">{rotuloAcao(it.acao)}</Td>
                {canEdit && (
                  <Td>
                    {!it.conferido && (
                      <Button size="sm" variant="ghost" aria-expanded={expandida === 'marcar'} onClick={() => setAberta(expandida === 'marcar' ? null : { item: it.item, modo: 'marcar' })}>
                        Marcar conferido
                      </Button>
                    )}
                  </Td>
                )}
              </Tr>,
              expandida && (
                <tr key={`${it.item}-x`} className="bg-[var(--surface-2)]">
                  <td colSpan={canEdit ? 6 : 5} className="px-3 py-2">
                    {expandida === 'ver'
                      ? <DadosExternos item={it.item} />
                      : <FormMarcar it={it} onCancelar={() => setAberta(null)} onConfirmar={(d, obs) => confirmarMarca(it.item, d, obs)} />}
                  </td>
                </tr>
              ),
            ];
          })}
        </tbody>
      </DataTable>
      {!linhas.length && <EmptyState title="Nenhum item neste recorte" hint="Mude a severidade ou o grupo." icon="check" />}
      {nPaginas > 1 && (
        <div className="flex items-center gap-2 mt-2 text-xs text-[var(--fg-3)] tabular">
          <Button size="sm" variant="ghost" disabled={pag === 0} onClick={() => setPagina(pag - 1)}>Anterior</Button>
          <span role="status">
            {(pag * POR_PAGINA + 1).toLocaleString('pt-BR')}–{Math.min((pag + 1) * POR_PAGINA, linhas.length).toLocaleString('pt-BR')} de {linhas.length.toLocaleString('pt-BR')}
          </span>
          <Button size="sm" variant="ghost" disabled={pag >= nPaginas - 1} onClick={() => setPagina(pag + 1)}>Próxima</Button>
        </div>
      )}
    </div>
  );
}

/** "Ver dados" de quem está fora da base: 1 chamada por abertura, descartada ao fechar a linha. */
function DadosExternos({ item }: { item: string }) {
  const [r, setR] = useState<Awaited<ReturnType<typeof loadConciliacaoRef>> | null>(null);
  useEffect(() => {
    let vivo = true;
    loadConciliacaoRef(item).then((x) => { if (vivo) setR(x); });
    return () => { vivo = false; };
  }, [item]);
  if (!r) return <p className="text-xs text-[var(--fg-3)]" role="status">Carregando…</p>;
  if (!r.ok) return <p className="text-xs text-[var(--red)]" role="alert">{r.erro}</p>;
  if (!r.data.length) return <p className="text-xs text-[var(--fg-3)]">Item já resolvido ou sem dados.</p>;
  return (
    <div className="grid gap-x-6 sm:grid-cols-2">
      {r.data.flatMap((linha, i) => Object.entries(linha).filter(([, v]) => v != null && v !== '').map(([k, v]) => (
        <div key={`${i}-${k}`} className="flex justify-between gap-3 py-1 border-b border-[var(--border-faint)]">
          <span className="text-xs text-[var(--fg-3)]">{ROTULO_CAMPO[k] ?? k.replace(/_/g, ' ')}</span>
          <span className="text-sm text-[var(--fg)] text-right">{valorExterno(k, v)}</span>
        </div>
      )))}
    </div>
  );
}

// Colunas de fn_aluno_conciliacao_ref.
const ROTULO_CAMPO: Record<string, string> = {
  fonte: 'Origem', nome: 'Nome', email: 'E-mail', produto: 'Produto', data: 'Data', valor: 'Valor',
};
function valorExterno(k: string, v: unknown): string {
  if (typeof v === 'number' && k.startsWith('valor')) return v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
  if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v)) return fmtData(v);
  return typeof v === 'object' ? JSON.stringify(v) : String(v);
}

function FormMarcar({ it, onCancelar, onConfirmar }: {
  it: ItemConciliacao;
  onCancelar: () => void;
  onConfirmar: (decisao: DecisaoConciliacao, obs: string) => void;
}) {
  const opcoes = decisoesDoTipo(it.tipo);
  const [decisao, setDecisao] = useState<DecisaoConciliacao>(opcoes[0]);
  const [obs, setObs] = useState('');
  return (
    <div className="flex flex-wrap items-end gap-3">
      {opcoes.length > 1 && (
        <fieldset className="flex flex-col">
          <legend className="text-xs text-[var(--fg-3)] mb-1">Decisão</legend>
          {opcoes.map((d) => (
            <label key={d} className="inline-flex items-center gap-2 text-sm text-[var(--fg)] cursor-pointer">
              <input type="radio" name={`dec-${it.item}`} checked={decisao === d} onChange={() => setDecisao(d)} className="accent-[var(--accent)]" />
              {ROTULO_DECISAO[d]}
            </label>
          ))}
        </fieldset>
      )}
      <label className="flex-1 min-w-[220px]">
        <span className="block text-xs text-[var(--fg-3)] mb-1">Observação (opcional)</span>
        <input
          value={obs}
          onChange={(e) => setObs(e.target.value)}
          maxLength={500}
          className="w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] text-[var(--fg)] px-3 py-1.5 text-sm focus:border-[var(--border-accent)]"
        />
      </label>
      <div className="flex gap-2">
        <Button size="sm" variant="ghost" onClick={onCancelar}>Cancelar</Button>
        <Button size="sm" onClick={() => onConfirmar(decisao, obs)}>Confirmar</Button>
      </div>
    </div>
  );
}
