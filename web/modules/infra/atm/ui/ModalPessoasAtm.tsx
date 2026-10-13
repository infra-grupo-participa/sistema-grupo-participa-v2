'use client';

import { useState, type ReactNode } from 'react';
import { ConfirmDialog, EmptyState, Loading, SkeletonRows, Toggle } from '@/shared/ui/components';
import { Modal } from '@/shared/ui/components/Modal';
import { RoscaCategorias } from '@/modules/infra/dados/ui/viz/RoscaCategorias';
import type { MetricaAtm, NumeroGrupoAtm } from '../domain/dashboard';
import { contadorDoModalAtm, cruzarComGrupoAtm, distribuicaoAtm, serieDiariaAtm, type DiaSerieAtm, type SituacaoGrupoAtm } from '../domain/modal-pessoas';
import { hojeEmSaoPaulo } from '../domain/periodo';
import type { EstadoListaAtm } from './carregador-listas';

/*
 * Modal de pessoas do funil do ATM: o modelo é o modal de Leads (decisão do Victor, 13/10/2026), com as abas
 * <pessoas> · Grupo · Evolução · Resumo, em tabela. Leads, Pré-checkout e Vendas usam este componente; muda só o que
 * cada conjunto tem (colunas, campos do resumo, como a aba Grupo é montada).
 */

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const hora = (d: Date | null) => (d ? d.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' }) : '');
export function dataHoraAtm(iso: string | null) { return iso ? new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : 'Não lançado'; }
export function simNaoAtm(v: boolean | null, nulo = 'Sem dado') { return v == null ? nulo : v ? 'Sim' : 'Não'; }

const CLASSE_TH = 'p-2 text-left text-xs';
const plural = (n: number, [um, varios]: [string, string]) => `${inteiro.format(n)} ${n === 1 ? um : varios}`;
const CLASSE_BOTAO = 'whitespace-nowrap rounded border border-[var(--border)] px-2 py-1 text-xs hover:bg-[var(--surface-3)] disabled:opacity-50';
const seloTeste = (extra = '') => <span className="rounded-full border border-[var(--border)] px-2 py-0.5 text-[10px] uppercase">teste{extra}</span>;

export type ColunaPessoasAtm<T> = { titulo: string; celula: (item: T) => ReactNode; className?: string };
export type CampoResumoPessoasAtm<T> = { nome: string; valor: (item: T, grupo: SituacaoGrupoAtm | undefined) => string; usaGrupo?: boolean };
export type AcaoTestePessoasAtm<T> = {
  disponivel: (item: T) => boolean;
  semAcao?: string;
  tituloConfirmacao: string;
  mensagemConfirmacao: string;
  executar: (item: T, teste: boolean) => Promise<string | null>;
};
export type GrupoPessoasAtm<T> =
  | { modo: 'numeros'; estado: EstadoListaAtm<NumeroGrupoAtm> | null; onToggle?: (numero: NumeroGrupoAtm, teste: boolean) => Promise<string | null> }
  | { modo: 'cruzamento'; estado: EstadoListaAtm<NumeroGrupoAtm> | null; telefoneDe: (item: T) => string | null; nomeDe: (item: T) => string | null };

export type PropsModalPessoasAtm<T extends { id: string; teste: boolean }> = {
  open: boolean;
  onClose: () => void;
  titulo: string;
  /** Rótulo da primeira aba (a tabela): "Leads" ou "Pessoas". */
  abaPessoas: string;
  /** Texto depois do número no contador, [singular, plural]: ["lead válido", "leads válidos"]. */
  rotuloContador: [string, string];
  /** Texto do centro das roscas. */
  rotuloCentro: string;
  periodoLabel: string;
  /** Período aplicado (AAAA-MM-DD), para o eixo da Evolução. */
  periodo: { de: string | null; ate: string | null };
  /** O card que abre o modal: o contador tem de bater com ele. */
  card: { rotulo: string; metrica: MetricaAtm };
  /** `null` = lista não pedida (sem permissão para ver contato). */
  lista: EstadoListaAtm<T> | null;
  /** Recorte local do conjunto (Vendas: período aplicado). */
  filtrar?: (data: T[]) => T[];
  colunas: ColunaPessoasAtm<T>[];
  rotuloData: string;
  dataDe: (item: T) => string | null;
  campos: CampoResumoPessoasAtm<T>[];
  grupo: GrupoPessoasAtm<T>;
  textos: { naoPublicada: string; vazio: string };
  bloqueio?: { titulo: string; hint: string } | null;
  notas?: ReactNode;
  isMaster: boolean;
  incluirTeste: boolean;
  onIncluirTeste: (v: boolean) => void;
  acaoTeste?: AcaoTestePessoasAtm<T>;
};

function GraficoDiario({ rows, rotulo }: { rows: DiaSerieAtm[]; rotulo: string }) {
  if (!rows.length) return <EmptyState title={`Sem evolução de ${rotulo}`} hint="nenhuma data no conjunto" />;
  const max = Math.max(1, ...rows.map((r) => r.quantidade));
  const width = Math.max(360, rows.length * 38);
  return <div className="overflow-x-auto"><svg width={width} height="190" viewBox={'0 0 ' + width + ' 190'} role="img" aria-label={`Evolução diária de ${rotulo}`}>
    {rows.map((r, i) => { const x = i * 38 + 8; const h = r.quantidade / max * 130; return <g key={r.dia}><rect x={x} y={145 - h} width="22" height={h} rx="3" fill="var(--accent)" /><text x={x + 11} y={140 - h} textAnchor="middle" fontSize="9" fill="var(--fg-2)">{r.quantidade}</text><text x={x + 11} y="166" textAnchor="middle" fontSize="9" fill="var(--fg-3)">{r.dia.slice(8, 10) + '/' + r.dia.slice(5, 7)}</text><title>{r.dia + ': ' + r.quantidade}</title></g>; })}
  </svg></div>;
}

function TabelaCarregando({ titulos }: { titulos: string[] }) {
  return <div className="max-h-[65vh] overflow-auto" aria-busy="true"><table className="w-full text-sm"><thead className="sticky top-0 bg-[var(--surface-3)]"><tr>{titulos.map((h) => <th key={h} className={CLASSE_TH}>{h}</th>)}</tr></thead>
    <tbody><SkeletonRows rows={8} avatar={false} cols={titulos.map((_, i) => (i === 0 ? 96 : 72))} /></tbody></table></div>;
}

/** Estado de uma lista que ainda não tem conteúdo para mostrar (carregando, erro, não publicada, sem permissão). `null` = tem conteúdo. */
function estadoSemConteudo<T>(estado: EstadoListaAtm<T> | null, carregando: ReactNode, naoPublicada: string): ReactNode | null {
  if (!estado || (estado.data === null && estado.fase === 'carregando')) return carregando;
  if (estado.fase === 'semPermissao') return <EmptyState title="Lista indisponível" hint="A permissão para ler esta lista foi perdida. Recarregue a página ou entre de novo." />;
  if (estado.fase === 'naoPublicada') return <EmptyState title={naoPublicada} hint="sem dado ainda" />;
  if (estado.data === null) return <p role="alert" className="rounded border border-[var(--yellow)]/40 p-3 text-sm text-[var(--yellow)]">{estado.erro}</p>;
  return null;
}

export function ModalPessoasAtm<T extends { id: string; teste: boolean }>(props: PropsModalPessoasAtm<T>) {
  const { open, onClose, titulo, abaPessoas, rotuloContador, rotuloCentro, periodoLabel, periodo, card, lista, filtrar, colunas, rotuloData, dataDe, campos, grupo, textos, bloqueio, notas, isMaster, incluirTeste, onIncluirTeste, acaoTeste } = props;
  const [aba, setAba] = useState(abaPessoas);
  const [alvo, setAlvo] = useState<T | null>(null);
  const [alvoNumero, setAlvoNumero] = useState<NumeroGrupoAtm | null>(null);
  const [salvando, setSalvando] = useState<string | null>(null);
  const [erroAcao, setErroAcao] = useState<string | null>(null);

  // Sem useMemo manual: o React Compiler do projeto memoiza (e as funções vêm novas a cada render do pai).
  const itens = lista?.data ? (filtrar ? filtrar(lista.data) : lista.data) : [];
  const contador = contadorDoModalAtm(itens);
  const cruzamento = grupo.modo === 'cruzamento' && grupo.estado?.data ? cruzarComGrupoAtm(itens, grupo.telefoneDe, grupo.estado.data) : null;
  const serie = aba === 'Evolução' ? serieDiariaAtm(itens, dataDe, periodo.de, periodo.ate, hojeEmSaoPaulo()) : [];
  const temLista = !bloqueio && !!lista?.data;
  const desatualizada = temLista && lista?.erro != null;
  const comAcao = isMaster && !!acaoTeste;
  const titulosTabela = [...colunas.map((c) => c.titulo), ...(comAcao ? ['Teste', 'Ação'] : [])];

  const contadorTexto = bloqueio ? `— · ${periodoLabel}`
    : temLista ? `${plural(contador, rotuloContador)} · ${periodoLabel} · lida às ${hora(lista!.lidoEm)}${lista!.revalidando ? ' · atualizando…' : ''}`
      : !lista || lista.fase === 'carregando' ? `Carregando… · ${periodoLabel}` : `— ${rotuloContador[1]} · ${periodoLabel}`;
  const diverge = temLista && !lista!.revalidando && !desatualizada && !card.metrica.semDado && card.metrica.valor !== contador;

  const executar = async (item: T, teste: boolean) => {
    if (salvando || !acaoTeste) return;
    setSalvando(item.id); setErroAcao(null); setAlvo(null);
    const erro = await acaoTeste.executar(item, teste);
    setSalvando(null);
    if (erro) setErroAcao(erro);
  };
  const executarNumero = async (numero: NumeroGrupoAtm, teste: boolean) => {
    if (salvando || grupo.modo !== 'numeros' || !grupo.onToggle) return;
    setSalvando(numero.foneKey); setErroAcao(null); setAlvoNumero(null);
    const erro = await grupo.onToggle(numero, teste);
    setSalvando(null);
    if (erro) setErroAcao(erro);
  };

  /** Envolve o conteúdo de uma aba que depende da lista principal. */
  const comLista = (carregando: ReactNode, conteudo: () => ReactNode): ReactNode => {
    if (bloqueio) return <EmptyState title={bloqueio.titulo} hint={bloqueio.hint} />;
    const vazio = estadoSemConteudo(lista, carregando, textos.naoPublicada);
    if (vazio) return vazio;
    if (itens.length === 0) return <EmptyState title={textos.vazio} hint={`lista lida às ${hora(lista!.lidoEm)}`} />;
    return <div className={desatualizada ? 'opacity-60' : ''}>{conteudo()}</div>;
  };

  const tabelaPessoas = () => <div className="max-h-[65vh] overflow-auto"><table className="w-full text-sm"><thead className="sticky top-0 bg-[var(--surface-3)]"><tr>{titulosTabela.map((h) => <th key={h} className={CLASSE_TH}>{h}</th>)}</tr></thead><tbody>
    {itens.map((item) => <tr key={item.id} className={'border-t border-[var(--border)] ' + (item.teste ? 'opacity-60' : '')}>
      {colunas.map((c) => <td key={c.titulo} className={'p-2 ' + (c.className ?? '')}>{c.celula(item)}</td>)}
      {comAcao && <><td className="p-2">{item.teste ? seloTeste() : 'Não'}</td><td className="p-2">{acaoTeste!.disponivel(item)
        ? <button type="button" disabled={salvando === item.id} onClick={() => { setErroAcao(null); if (item.teste) void executar(item, false); else setAlvo(item); }} className={CLASSE_BOTAO}>{salvando === item.id ? 'Salvando…' : item.teste ? 'Desmarcar teste' : 'Marcar como teste'}</button>
        : acaoTeste!.semAcao ?? null}</td></>}
    </tr>)}
  </tbody></table></div>;

  const abaGrupoNumeros = (g: Extract<GrupoPessoasAtm<T>, { modo: 'numeros' }>) => {
    const titulos = ['Entrada', 'Nome', 'Telefone', 'No grupo?', 'É lead?', ...(isMaster ? ['Teste', 'Ação'] : [])];
    const vazio = estadoSemConteudo(g.estado, <TabelaCarregando titulos={titulos} />, 'Números do grupo indisponíveis');
    if (vazio) return vazio;
    const numeros = g.estado!.data!;
    const velho = g.estado!.erro != null;
    return <>
      {velho && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{g.estado!.erro} Mostrando os números lidos às {hora(g.estado!.lidoEm)}.</p>}
      {numeros.length === 0 ? <EmptyState title="Nenhum número entrou no grupo neste período" hint={`lista lida às ${hora(g.estado!.lidoEm)}`} /> : <div className={'max-h-[65vh] overflow-auto ' + (velho ? 'opacity-60' : '')}><table className="w-full text-sm"><thead className="sticky top-0 bg-[var(--surface-3)]"><tr>{titulos.map((h) => <th key={h} className={CLASSE_TH}>{h}</th>)}</tr></thead><tbody>{numeros.map((numero) => <tr key={numero.foneKey} className={'border-t border-[var(--border)] ' + (numero.teste ? 'opacity-60' : '')}><td className="whitespace-nowrap p-2">{dataHoraAtm(numero.entrouEm)}</td><td className="p-2">{numero.nome ?? 'Não lançado'}</td><td className="whitespace-nowrap p-2">{numero.foneKey}</td><td className="p-2">{simNaoAtm(numero.noGrupo, 'Não lançado')}</td><td className="p-2">{simNaoAtm(numero.ehLead, 'Não lançado')}</td>{isMaster && <><td className="p-2">{numero.teste ? seloTeste(numero.testeMotivo === 'equipe' ? ' · equipe' : '') : 'Não'}</td><td className="p-2">{g.onToggle && <button type="button" disabled={salvando === numero.foneKey} onClick={() => { setErroAcao(null); if (numero.teste) void executarNumero(numero, false); else setAlvoNumero(numero); }} className={CLASSE_BOTAO}>{salvando === numero.foneKey ? 'Salvando…' : numero.teste ? 'Desmarcar teste' : 'Marcar como teste'}</button>}</td></>}</tr>)}</tbody></table></div>}
    </>;
  };

  const abaGrupoCruzamento = (g: Extract<GrupoPessoasAtm<T>, { modo: 'cruzamento' }>) => {
    const titulos = [rotuloData, 'Nome', 'Telefone', 'Entrou no grupo?', 'Entrada no grupo', 'Ainda no grupo?'];
    return comLista(<TabelaCarregando titulos={titulos} />, () => {
      const vazio = estadoSemConteudo(g.estado, <TabelaCarregando titulos={titulos} />, 'Números do grupo indisponíveis');
      if (vazio) return vazio;
      const validos = itens.filter((i) => !i.teste);
      const noGrupo = validos.filter((i) => { const s = cruzamento?.get(i.id); return s && !s.semTelefone && s.numero; }).length;
      const semTelefone = validos.filter((i) => cruzamento?.get(i.id)?.semTelefone).length;
      return <>
        <p className="mb-3 text-xs text-[var(--fg-3)]">{inteiro.format(noGrupo)} de {plural(validos.length, rotuloContador)} {noGrupo === 1 ? 'está ou esteve' : 'estão ou estiveram'} no grupo (cruzamento pelo telefone, DDD + 8 últimos dígitos, com os números do grupo no período do evento){semTelefone ? ` · ${inteiro.format(semTelefone)} sem telefone para cruzar` : ''} · números lidos às {hora(g.estado!.lidoEm)}</p>
        {g.estado!.erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{g.estado!.erro}</p>}
        <div className="max-h-[65vh] overflow-auto"><table className="w-full text-sm"><thead className="sticky top-0 bg-[var(--surface-3)]"><tr>{titulos.map((h) => <th key={h} className={CLASSE_TH}>{h}</th>)}</tr></thead><tbody>{itens.map((item) => {
          const s = cruzamento?.get(item.id);
          const n = s && !s.semTelefone ? s.numero : null;
          return <tr key={item.id} className={'border-t border-[var(--border)] ' + (item.teste ? 'opacity-60' : '')}>
            <td className="whitespace-nowrap p-2">{dataHoraAtm(dataDe(item))}</td><td className="p-2">{g.nomeDe(item) ?? 'Não lançado'}</td><td className="whitespace-nowrap p-2">{g.telefoneDe(item) ?? 'Sem telefone'}</td>
            <td className="p-2">{!s || s.semTelefone ? 'Sem dado' : n ? 'Sim' : 'Não'}</td><td className="whitespace-nowrap p-2">{n ? dataHoraAtm(n.entrouEm) : '—'}</td><td className="p-2">{n ? simNaoAtm(n.noGrupo) : '—'}</td>
          </tr>;
        })}</tbody></table></div>
      </>;
    });
  };

  const abaResumo = () => comLista(<Loading />, () => <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{campos.map((campo) => {
    if (campo.usaGrupo && grupo.modo === 'cruzamento' && !cruzamento) {
      const g = grupo.estado;
      return <section key={campo.nome} className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4"><h3 className="mb-3 text-sm font-semibold text-[var(--fg)]">{campo.nome}</h3><p className="text-xs text-[var(--fg-3)]">{!g || g.fase === 'carregando' ? 'Carregando os números do grupo…' : g.fase === 'naoPublicada' ? 'Números do grupo indisponíveis' : g.erro ?? 'Sem dado'}</p></section>;
    }
    return <RoscaCategorias key={campo.nome} titulo={campo.nome} rotuloCentro={rotuloCentro} fatias={distribuicaoAtm(itens, (item) => campo.valor(item, cruzamento?.get(item.id)))} />;
  })}</div>);

  const conteudo = aba === 'Grupo'
    ? (grupo.modo === 'numeros' ? abaGrupoNumeros(grupo) : abaGrupoCruzamento(grupo))
    : aba === 'Evolução' ? comLista(<Loading />, () => <GraficoDiario rows={serie} rotulo={rotuloCentro} />)
      : aba === 'Resumo' ? abaResumo()
        : comLista(<TabelaCarregando titulos={titulosTabela} />, tabelaPessoas);

  return <Modal open={open} onClose={() => { setErroAcao(null); onClose(); }} title={titulo} width="max-w-6xl">
    <div className="mb-4 flex flex-wrap items-center gap-2">
      {[abaPessoas, 'Grupo', 'Evolução', 'Resumo'].map((nome) => <button key={nome} type="button" onClick={() => setAba(nome)} className={'rounded-[var(--r-md)] px-3 py-2 text-sm ' + (aba === nome ? 'bg-[var(--accent)] text-black font-semibold' : 'bg-[var(--surface-3)] text-[var(--fg-2)]')}>{nome}</button>)}
      {isMaster && !bloqueio && <span className="ml-2 text-xs"><Toggle checked={incluirTeste} onChange={onIncluirTeste} label="Incluir testes" /></span>}
      <span className="ml-auto self-center text-xs text-[var(--fg-3)]" aria-live="polite">{contadorTexto}</span>
    </div>
    {notas}
    {desatualizada && <p role="status" className="mb-3 rounded border border-[var(--yellow)]/40 p-3 text-sm text-[var(--yellow)]">{lista!.erro} Mostrando a lista lida às {hora(lista!.lidoEm)}.</p>}
    {diverge && <p role="status" className="mb-3 text-xs text-[var(--yellow)]">Card {card.rotulo}: {inteiro.format(card.metrica.valor)} · esta lista: {inteiro.format(contador)}. Precisa conferir antes de usar o número (clique em Atualizar na página para reler os dois).</p>}
    {erroAcao && <p role="alert" className="mb-3 rounded border border-[var(--red)]/40 p-3 text-sm text-[var(--red)]">{erroAcao}</p>}
    {conteudo}
    {alvo && acaoTeste && <ConfirmDialog title={acaoTeste.tituloConfirmacao} confirmLabel="Marcar como teste" cancelLabel="Cancelar" onCancel={() => setAlvo(null)} onConfirm={() => void executar(alvo, true)} message={acaoTeste.mensagemConfirmacao} />}
    {alvoNumero && <ConfirmDialog title="Marcar número do grupo como teste" confirmLabel="Marcar como teste" cancelLabel="Cancelar" onCancel={() => setAlvoNumero(null)} onConfirm={() => void executarNumero(alvoNumero, true)} message="Esta marcação vale para este Seminário ATM. O número e os dados relacionados deixam de contar nos indicadores deste evento. Quer continuar?" />}
  </Modal>;
}
