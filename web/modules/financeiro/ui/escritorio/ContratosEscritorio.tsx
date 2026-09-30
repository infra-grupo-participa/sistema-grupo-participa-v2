'use client';

// Escritório › Contratos (z93, 30/09/2026): contratos da Holding Familiar mês a mês. Parte do pagamento cai na Hotmart
// (baixa automática, cron :25) e o resto vem por Pix (baixa manual). A tela só exibe: situação, casamento com a Hotmart,
// "fecha em" e o que conta em cada mês vêm prontos do SQL (fn_fin_contratos_hf_mensal / _pagamentos).
// - Consultas: ver application/carregar-contratos-hf.ts (grade 1× por página; pagamentos = a sonda da sub-aba).
// - Escrita (ficha, concluir etapa, baixa Pix, arquivar, desfundir): só com canEdit (podeOperarFinanceiro, resolvido no
//   servidor e descido por prop). A trava real é o banco: gp_pode_operar_financeiro() em cada RPC.
// - Texto do cliente (nome, e-mail, observação, link) só entra por JSX — nunca dangerouslySetInnerHTML. O link do
//   contrato só vira <a href> se passar na MESMA regex do banco (linkContratoSeguro); fora dela, texto.
// - Nada `absolute`: confirmações e formulários ficam no fluxo (célula, linha ou ficha).
import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { DataTable, Drawer, Loading, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtBRLc, fmtData, fmtDataHora } from '@/shared/ui/format';
import type { FinanceiroRepository, Resultado } from '../../application/ports';
import { RecursoAusenteError } from '../../application/ports';
import {
  entradaNovaParcela, repoColagemNoContrato, type CacheContratosHF, type ConfirmarNomes,
} from '../../application/carregar-contratos-hf';
import {
  baixaPelaHotmart, formDaFicha, lerMotivoFila, linkContratoSeguro, montarGradeContratos, motivoValido, parcelasDoContrato,
  nomesDiferentesDaFicha, payloadFicha, podeDesfundir, type ContratoNaGrade, type FichaContratoHF, type FormFichaContrato,
  type LinhaMensalContratoHF, type PagamentoContratoHF, type ParcelaContratoHF, type SyncStatusContratosHF,
} from '../../domain/contratos-hf';
import { formDeInformado, TIPO_CONTRATO, type FormInformado } from '../../domain/recebimentos-informados';
import { ColarDaPlanilha, FormularioInformado } from '../receber/Informados';
import { Erro } from '../hotmart/comum';

export type RepoContratosEscrita = Pick<FinanceiroRepository,
  'salvarContratoHf' | 'concluirEtapaParcela' | 'desfundirContratoHf' | 'baixarInformado' | 'salvarInformado' | 'importarInformados'>;

const NUM = 'tabular text-right whitespace-nowrap';
const BTN = 'rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-xs text-[var(--fg-2)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const BTN_1 = 'rounded-[var(--r-sm)] border border-[var(--accent)] px-2 py-0.5 text-xs font-semibold text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const INPUT = 'rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1 text-xs text-[var(--fg)]';
/** Caiu na Hotmart × caiu à mão (Pix): cor + letra (a cor nunca é o único sinal). */
const COR_HOTMART = 'text-[var(--cyan)]';
const COR_MANUAL = 'text-[var(--purple)]';
/** 1ª coluna fixa ao rolar a grade para o lado (o DataTable rola em x no próprio contêiner). Fundo opaco igual ao da
 *  faixa (senão os meses passam por baixo aparecendo) e a divisa por sombra interna: com border-collapse a borda da
 *  célula sticky não acompanha. O DataTable compartilhado não tem coluna fixa — só esta tabela usa. */
const FIXA = 'sticky left-0 z-[2] min-w-[180px] max-w-[260px] shadow-[inset_-1px_0_0_var(--border)]';

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const fmtMes = (m: string) => `${MESES[Number(m.slice(5, 7)) - 1]}/${m.slice(2, 4)}`;
const hojeISO = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date());
const ROTULO_ASSINADO: Record<string, string> = { sim: 'Sim', nao: 'Não', indeterminado: 'Indeterminado' };
const ROTULO_ORIGEM: Record<string, string> = { hotmart_sinal: 'Criado pelo sinal na Hotmart', planilha_drive: 'Planilha do Drive' };
const ROTULO_SITUACAO: Record<string, string> = {
  em_atraso_cobrar: 'Em atraso — cobrar', a_receber: 'A receber', baixado_fora: 'Baixado fora',
  baixado_hotmart: 'Baixado pela Hotmart', a_receber_etapa: 'A receber na etapa', recebido_sem_parcela: 'Recebido sem parcela',
};
const rotuloParcela = (p: ParcelaContratoHF) => (p.parcela_n != null && p.parcela_de != null ? `${p.parcela_n} de ${p.parcela_de}` : '—');
/** A baixa automática chega do banco como 'baixado_fora' (texto da z73): a tela diz "Baixado pela Hotmart". */
const situacaoParcela = (p: ParcelaContratoHF) => (p.situacao === 'baixado_fora' && baixaPelaHotmart(p) ? 'baixado_hotmart' : p.situacao);
const msgErro = (e: unknown, padrao: string) =>
  (e instanceof RecursoAusenteError ? 'Contratos da Holding Familiar ainda não disponíveis no banco.' : e instanceof Error ? e.message : padrao);

type Estado<T> = { dados: T | null; erro: string | null } | null;
export type Aviso = { tipo: 'ok' | 'erro'; msg: string } | null;
/** Concluir etapa ou baixar (Pix) aberto numa parcela: a data digitada. */
export type AcaoParcela = { id: string; tipo: 'etapa' | 'baixar'; data: string } | null;

export function ContratosEscritorio({ cache, repo, canEdit, canVerDoc, onAlterado }: {
  cache: CacheContratosHF; repo: RepoContratosEscrita; canEdit: boolean; canVerDoc: boolean;
  /** Depois de gravar: a previsão de caixa (bloco 7) muda — o pai invalida o Contas a Receber. */
  onAlterado?: () => void;
}) {
  const [grade, setGrade] = useState<Estado<LinhaMensalContratoHF[]>>(null);
  const [pags, setPags] = useState<Estado<PagamentoContratoHF[]>>(null);
  const [sync, setSync] = useState<Estado<SyncStatusContratosHF>>(null);
  const [versao, setVersao] = useState(0);
  const [abertoId, setAbertoId] = useState<string | null>(null);
  const [aviso, setAviso] = useState<Aviso>(null);
  const [ocupado, setOcupado] = useState(false);
  const [acao, setAcao] = useState<AcaoParcela>(null);

  // Busca e aplica só no retorno (setState em callback assíncrono). Depois de gravar, `versao` muda: a grade atual fica
  // na tela até a nova chegar (sem piscar "carregando").
  useEffect(() => {
    let vivo = true;
    if (!cache.gradeLida()) {
      cache.grade().then(
        (d) => { if (vivo) setGrade({ dados: d, erro: null }); },
        (e: unknown) => { if (vivo) setGrade((g) => ({ dados: g?.dados ?? null, erro: msgErro(e, 'Não foi possível carregar os contratos.') })); },
      );
    }
    if (!cache.pagamentosLidos()) {
      cache.pagamentos().then(
        (d) => { if (vivo) setPags({ dados: d, erro: null }); },
        (e: unknown) => { if (vivo) setPags((g) => ({ dados: g?.dados ?? null, erro: msgErro(e, 'Não foi possível carregar a conferência da Hotmart.') })); },
      );
    }
    if (!cache.syncLido()) {
      cache.sync().then(
        (d) => { if (vivo) setSync({ dados: d, erro: null }); },
        (e: unknown) => { if (vivo) setSync({ dados: null, erro: msgErro(e, 'Não foi possível ler o status da sincronização com a Hotmart.') }); },
      );
    }
    return () => { vivo = false; };
  }, [cache, versao]);

  const linhas = cache.gradeLida() ?? grade?.dados ?? null;
  const pagamentos = cache.pagamentosLidos() ?? pags?.dados ?? null;
  const statusSync = cache.syncLido() ?? sync?.dados ?? null;

  const executar = async (f: () => Promise<Resultado>, aoConcluir?: () => void): Promise<boolean> => {
    setOcupado(true);
    setAviso(null);
    try {
      const r = await f();
      if (!r.ok) { setAviso({ tipo: 'erro', msg: r.msg ?? 'Não foi possível concluir.' }); return false; }
      aoConcluir?.();
      setAviso({ tipo: 'ok', msg: r.msg ?? 'Feito.' });
      // O que está na tela fica até a releitura chegar: sem isso, a grade que veio do cache (sem cópia no estado) viraria
      // "carregando" e a ficha aberta desmontaria junto com o aviso.
      setGrade({ dados: linhas, erro: null });
      setPags({ dados: pagamentos, erro: null });
      cache.invalidar();
      setVersao((v) => v + 1);
      onAlterado?.();
      return true;
    } finally {
      setOcupado(false);
    }
  };
  const acoesParcela = {
    acao, setAcao, ocupado, canEdit,
    confirmar: (a: NonNullable<AcaoParcela>) => void executar(
      () => (a.tipo === 'etapa' ? repo.concluirEtapaParcela(a.id, a.data) : repo.baixarInformado(a.id, a.data)),
      () => setAcao(null),
    ),
    desfazerBaixa: (id: string) => void executar(() => repo.baixarInformado(id, null)),
  };

  if (!linhas && grade?.erro) {
    return (
      <div className="space-y-2">
        <Erro msg={grade.erro} />
        <button type="button" className={BTN} onClick={() => { setGrade(null); setVersao((v) => v + 1); }}>Tentar de novo</button>
      </div>
    );
  }
  if (!linhas) return <Loading label="Carregando os contratos…" minHeight={240} />;

  const g = montarGradeContratos(linhas);
  const aberto = abertoId ? g.contratos.find((c) => c.ficha.id === abertoId) ?? null : null;
  const nCols = 6 + g.meses.length;

  return (
    <div className="space-y-4">
      <SyncHotmart s={statusSync} erro={sync?.erro ?? null} />
      {aviso && !aberto && <AvisoLinha aviso={aviso} />}
      {grade?.erro && (
        // Releitura depois de gravar falhou: a grade anterior continua na tela, com o aviso de que pode estar velha.
        <p role="alert" className="text-xs font-semibold text-[var(--red)]">
          {grade.erro} A grade abaixo pode estar desatualizada.{' '}
          <button type="button" className={BTN} onClick={() => { setGrade((x) => (x ? { ...x, erro: null } : x)); setVersao((v) => v + 1); }}>Tentar de novo</button>
        </p>
      )}

      <section className="space-y-1" aria-labelledby="contratos-hf-titulo">
        <h2 id="contratos-hf-titulo" className="text-sm font-semibold text-[var(--fg)]">
          Contratos Holding Familiar <span className="font-normal text-[var(--fg-3)]">{g.contratos.length}</span>
        </h2>
        <p className="text-[11px] text-[var(--fg-3)]">
          Em cada mês: esperado · <span className={COR_HOTMART}>H</span> caiu na Hotmart · <span className={COR_MANUAL}>M</span> caiu
          por baixa manual (Pix).{!canEdit && ' Somente leitura: editar e concluir etapa exigem permissão de operar o financeiro.'}
        </p>
        <DataTable minWidth={760 + g.meses.length * 96}>
          <Thead>
            <Th className={`${FIXA} bg-[var(--surface-3)]`}>Cliente</Th>
            <Th className="text-right">Valor cheio</Th>
            <Th>Assinado</Th>
            <Th>Contrato</Th>
            {g.meses.map((m) => <Th key={m} className="text-right">{fmtMes(m)}</Th>)}
            <Th>A receber na etapa</Th>
            <Th className="text-right">Total</Th>
          </Thead>
          <tbody>
            {g.contratos.length === 0 ? (
              <tr><td colSpan={nCols} className="px-3 py-3 text-xs text-[var(--fg-3)]">Nenhum contrato no período.</td></tr>
            ) : g.contratos.map((c) => (
              <LinhaContrato key={c.ficha.id} c={c} meses={g.meses} onAbrir={() => { setAviso(null); setAcao(null); setAbertoId(c.ficha.id); }}
                acoes={acoesParcela} />
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t-2 border-[var(--border-strong)] font-semibold text-[var(--fg)]">
              <td className={`px-3 py-2 ${FIXA} bg-[var(--surface-2)]`}>Total</td>
              <td className="px-3 py-2" colSpan={3} />
              {g.meses.map((m) => <td key={m} className={`px-3 py-2 ${NUM}`}><Valores s={g.totalMes[m]} /></td>)}
              <td className={`px-3 py-2 ${NUM}`}>{g.totalEtapa > 0 ? fmtBRL(g.totalEtapa) : '—'}</td>
              <td className={`px-3 py-2 ${NUM}`}><Valores s={g.total} /></td>
            </tr>
          </tfoot>
        </DataTable>
      </section>

      <FilaConferencia pagamentos={pagamentos} erro={pags?.erro ?? null} />

      {aberto && (
        <FichaContrato key={aberto.ficha.id} c={aberto} repo={repo} canEdit={canEdit} canVerDoc={canVerDoc}
          ocupado={ocupado} aviso={aviso} executar={executar} acoes={acoesParcela}
          onClose={() => { setAbertoId(null); setAcao(null); }} />
      )}
    </div>
  );
}

function AvisoLinha({ aviso }: { aviso: NonNullable<Aviso> }) {
  return (
    <p role={aviso.tipo === 'erro' ? 'alert' : 'status'}
      className={`text-xs ${aviso.tipo === 'erro' ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-2)]'}`}>{aviso.msg}</p>
  );
}

/** Esperado em cima; embaixo o que caiu, separado por origem. Zero não é pintado. */
function Valores({ s, atraso = false }: { s: { esperado: number; caiu_hotmart: number; caiu_manual: number }; atraso?: boolean }) {
  if (!s.esperado && !s.caiu_hotmart && !s.caiu_manual) return <span className="text-[var(--fg-4)]">—</span>;
  return (
    <>
      <span className={`block ${atraso ? 'font-semibold text-[var(--red)]' : ''}`}>{s.esperado ? fmtBRL(s.esperado) : '—'}</span>
      {s.caiu_hotmart > 0 && <span className={`block text-[11px] ${COR_HOTMART}`}>H {fmtBRL(s.caiu_hotmart)}</span>}
      {s.caiu_manual > 0 && <span className={`block text-[11px] ${COR_MANUAL}`}>M {fmtBRL(s.caiu_manual)}</span>}
    </>
  );
}

/** Link seguro vira <a>; o que não passa na regex do banco vira texto (nunca href). */
export function LinkContrato({ link, rotulo = 'abrir' }: { link: string | null; rotulo?: string }) {
  if (!link) return <span className="text-[var(--fg-4)]">—</span>;
  const seguro = linkContratoSeguro(link);
  if (!seguro) return <span className="break-all text-[11px] text-[var(--fg-3)]">{link}</span>;
  return <a href={seguro} target="_blank" rel="noopener noreferrer" className="text-[var(--accent)] underline underline-offset-2">{rotulo}</a>;
}

export type AcoesParcela = {
  acao: AcaoParcela; setAcao: (a: AcaoParcela) => void; ocupado: boolean; canEdit: boolean;
  confirmar: (a: NonNullable<AcaoParcela>) => void; desfazerBaixa: (id: string) => void;
};

function LinhaContrato({ c, meses, onAbrir, acoes }: { c: ContratoNaGrade; meses: string[]; onAbrir: () => void; acoes: AcoesParcela }) {
  const f = c.ficha;
  return (
    <Tr>
      <Td className={`text-xs ${FIXA} bg-[var(--surface-2)]`}>
        {/* Só o nome abre a ficha: a linha tem link e botões próprios (linha inteira clicável mudaria o contrato deles). */}
        <button type="button" onClick={onAbrir} className="text-left font-medium text-[var(--fg)] underline-offset-2 hover:underline">
          {f.nome ?? '—'}
        </button>
        {f.arquivado_em && <span className="block text-[10px] text-[var(--fg-3)]">arquivado</span>}
      </Td>
      <Td className={`${NUM} text-xs`}>{fmtBRL(f.valor_bruto)}</Td>
      <Td className="text-xs whitespace-nowrap">
        {ROTULO_ASSINADO[f.assinado] ?? f.assinado}
        {f.data_assinatura && <span className="block text-[10px] text-[var(--fg-3)]">{fmtData(f.data_assinatura)}</span>}
      </Td>
      <Td className="text-xs"><LinkContrato link={f.link_contrato} /></Td>
      {meses.map((m) => {
        const cel = c.meses[m];
        return (
          <Td key={m} className={`${NUM} text-xs`}>
            {cel ? <Valores s={cel} atraso={cel.situacao === 'em_atraso_cobrar'} /> : <span className="text-[var(--fg-4)]">—</span>}
          </Td>
        );
      })}
      <Td className="text-xs">
        {c.etapa && c.etapa.parcelas.length > 0
          ? c.etapa.parcelas.map((p) => <ParcelaEtapa key={p.id} p={p} acoes={acoes} />)
          : <span className="text-[var(--fg-4)]">—</span>}
      </Td>
      <Td className={`${NUM} text-xs`}><Valores s={c.total} /></Td>
    </Tr>
  );
}

/** "a receber na etapa X": valor + etapa; quem opera conclui a etapa com a data (entra na previsão). */
function ParcelaEtapa({ p, acoes }: { p: ParcelaContratoHF; acoes: AcoesParcela }) {
  const aberta = acoes.acao?.id === p.id && acoes.acao.tipo === 'etapa' ? acoes.acao : null;
  return (
    <div className="py-0.5">
      <span className="tabular whitespace-nowrap">{fmtBRL(p.valor)}</span>
      <span className="text-[var(--fg-3)]"> · {p.etapa ?? 'etapa'}</span>
      {acoes.canEdit && !aberta && (
        <button type="button" className={`${BTN} ml-1`} disabled={acoes.ocupado}
          onClick={() => acoes.setAcao({ id: p.id, tipo: 'etapa', data: hojeISO() })}>Concluir etapa</button>
      )}
      {acoes.canEdit && aberta && <ConfirmarData acao={aberta} acoes={acoes} rotulo="Etapa concluída em" confirmar="Confirmar" />}
    </div>
  );
}

function ConfirmarData({ acao, acoes, rotulo, confirmar }: { acao: NonNullable<AcaoParcela>; acoes: AcoesParcela; rotulo: string; confirmar: string }) {
  return (
    <span className="mt-1 flex flex-wrap items-center gap-1">
      <label className="flex items-center gap-1 text-[11px] text-[var(--fg-2)]">
        {rotulo}
        <input type="date" className={INPUT} value={acao.data} max={hojeISO()} onChange={(e) => acoes.setAcao({ ...acao, data: e.target.value })} />
      </label>
      <button type="button" className={BTN_1} disabled={acoes.ocupado || !acao.data} onClick={() => acoes.confirmar(acao)}>{confirmar}</button>
      <button type="button" className={BTN} onClick={() => acoes.setAcao(null)}>Cancelar</button>
    </span>
  );
}

/**
 * Status da última sincronização com a Hotmart (cron :25), lido de fn_fin_contratos_hf_sync_status — 1 linha sempre,
 * independente da fila (fila vazia não quer dizer "sem erro"). Erro = faixa de aviso com a mensagem do banco.
 */
function SyncHotmart({ s, erro }: { s: SyncStatusContratosHF | null; erro: string | null }) {
  if (!s && erro) return <p role="alert" className="text-xs font-semibold text-[var(--red)]">{erro}</p>;
  if (!s) return <p className="text-[11px] text-[var(--fg-3)]">Lendo o status da sincronização com a Hotmart…</p>;
  if (!s.ultima_em) return <p className="text-[11px] text-[var(--fg-3)]">A sincronização com a Hotmart ainda não rodou: nenhuma baixa automática até ela rodar.</p>;
  const n = s.erros ?? 0;
  if (n > 0) {
    return (
      <div role="alert" className="rounded-[var(--r-md)] border border-[var(--yellow)] px-3 py-2 text-xs text-[var(--fg)]">
        <span className="font-semibold">Sincronização com a Hotmart: {n} {n === 1 ? 'erro' : 'erros'}</span> em {fmtDataHora(s.ultima_em)}.
        {' '}Baixas automáticas podem estar atrasadas.
        {s.mensagem && <span className="mt-1 block whitespace-pre-wrap text-[var(--fg-2)]">{s.mensagem}</span>}
      </div>
    );
  }
  return <p className="text-[11px] text-[var(--fg-3)]">Última sincronização com a Hotmart: {fmtDataHora(s.ultima_em)}, sem erro.</p>;
}

/** Pagamentos HF da Hotmart que não casaram com nenhuma parcela, com o motivo. */
function FilaConferencia({ pagamentos, erro }: { pagamentos: PagamentoContratoHF[] | null; erro: string | null }) {
  const fila = (pagamentos ?? []).filter((p) => p.situacao === 'fila');
  return (
    <section className="space-y-1" aria-labelledby="contratos-fila-titulo">
      <h2 id="contratos-fila-titulo" className="text-sm font-semibold text-[var(--fg)]">
        Conferência da Hotmart {pagamentos && <span className="font-normal text-[var(--fg-3)]">{fila.length}</span>}
      </h2>
      {!pagamentos && erro ? <Erro msg={erro} /> : !pagamentos ? <Loading label="Carregando a conferência…" minHeight={80} /> : fila.length === 0 ? (
        <p className="text-xs text-[var(--fg-3)]">Nenhum pagamento da Hotmart esperando conferência.</p>
      ) : (
        <DataTable minWidth={980}>
          <Thead>
            <Th>Dia</Th><Th>Comprador na Hotmart</Th><Th className="text-right">Valor</Th><Th>Transação</Th><Th>Contrato</Th><Th>Por que não casou</Th>
          </Thead>
          <tbody>
            {fila.map((p) => {
              const m = lerMotivoFila(p.motivo);
              return (
                <Tr key={p.transacao}>
                  <Td className="tabular text-xs whitespace-nowrap">{fmtData(p.dia)}</Td>
                  <Td className="text-xs">{p.nome_hotmart ?? '—'}<span className="block text-[11px] text-[var(--fg-3)]">{p.email_hotmart ?? ''}</span></Td>
                  <Td className={`${NUM} text-xs`}>{fmtBRLc(p.valor)}</Td>
                  <Td className="font-mono text-[11px] text-[var(--fg-2)]">{p.transacao}</Td>
                  <Td className="text-xs">{p.contrato_nome ?? '—'}</Td>
                  <Td className="text-xs"><span className="font-semibold">{m.rotulo}</span>{m.frase && <span className="block text-[var(--fg-2)]">{m.frase}</span>}</Td>
                </Tr>
              );
            })}
          </tbody>
        </DataTable>
      )}
    </section>
  );
}

type Painel = 'editar' | 'arquivar' | 'desfundir' | 'nova' | 'colar' | null;

export function FichaContrato({ c, repo, canEdit, canVerDoc, ocupado, aviso, executar, acoes, onClose }: {
  c: ContratoNaGrade; repo: RepoContratosEscrita; canEdit: boolean; canVerDoc: boolean; ocupado: boolean; aviso: Aviso;
  executar: (f: () => Promise<Resultado>, aoConcluir?: () => void) => Promise<boolean>; acoes: AcoesParcela; onClose: () => void;
}) {
  const f = c.ficha;
  const [painel, setPainel] = useState<Painel>(null);
  const [form, setForm] = useState<FormFichaContrato>(() => formDaFicha(f));
  const [erros, setErros] = useState<string[]>([]);
  const [motivo, setMotivo] = useState('');
  const [nova, setNova] = useState<{ valores: FormInformado; erros: string[] }>(() => novaParcela(f, canVerDoc));
  const parcelas = parcelasDoContrato(c);
  const vivo = !f.arquivado_em;
  // Nome enviado diferente do da ficha: o banco grava com o nome da ficha e guarda o enviado na observação. A tela pergunta antes.
  const [confirmacao, setConfirmacao] = useState<{ origem: 'planilha' | 'formulario'; nomes: string[]; responder: (ok: boolean) => void } | null>(null);
  const perguntar = (origem: 'planilha' | 'formulario'): ConfirmarNomes => (nomes) => new Promise<boolean>((res) => {
    setConfirmacao({ origem, nomes, responder: (ok) => { setConfirmacao(null); res(ok); } });
  });
  // Memo: o adaptador lembra os nomes já confirmados entre "Conferir" e "Gravar" (não pergunta duas vezes).
  const repoColar = useMemo(() => repoColagemNoContrato(repo, f.id, f.nome, perguntar('planilha')), [repo, f.id, f.nome]);
  const abrir = (p: Painel) => { setErros([]); setMotivo(''); setPainel((x) => (x === p ? null : p)); };

  const salvar = () => {
    const r = payloadFicha(form, f);
    if (!r.p) { setErros(r.erros); return; }
    const p = r.p;
    void executar(() => repo.salvarContratoHf(p), () => setPainel(null));
  };

  const contato = [f.email, f.telefone, f.cidade && f.uf ? `${f.cidade}/${f.uf}` : f.cidade ?? f.uf, f.cpf_final3 ? `CPF final ${f.cpf_final3}` : null]
    .filter(Boolean).join(' · ');

  return (
    <Drawer onClose={onClose} width="max-w-5xl" title={f.nome ?? '—'} subtitle={contato || undefined}>
      <div className="space-y-4 text-xs">
        {aviso && <AvisoLinha aviso={aviso} />}
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 md:grid-cols-4">
          <Dado r="Valor cheio">{fmtBRLc(f.valor_bruto)}</Dado>
          <Dado r="Valor líquido">{fmtBRLc(f.valor_liquido)}</Dado>
          <Dado r="Entrada">{f.entrada_valor != null ? fmtBRLc(f.entrada_valor) : '—'}{f.entrada_pct != null && ` (${f.entrada_pct.toLocaleString('pt-BR')}%)`}</Dado>
          <Dado r="Desconto">{f.desconto_desc ?? '—'}</Dado>
          <Dado r="Assinado">{ROTULO_ASSINADO[f.assinado] ?? f.assinado}{f.data_assinatura && ` em ${fmtData(f.data_assinatura)}`}</Dado>
          <Dado r="Fechado em">{fmtData(f.fechado_em)}</Dado>
          <Dado r="Origem">{ROTULO_ORIGEM[f.origem] ?? f.origem}</Dado>
          <Dado r="Sinal na Hotmart"><span className="font-mono">{f.transacao_sinal ?? '—'}</span></Dado>
          <Dado r="Contrato"><LinkContrato link={f.link_contrato} rotulo="abrir o contrato" /></Dado>
          {f.arquivado_em && <Dado r="Arquivado em">{fmtData(f.arquivado_em.slice(0, 10))}</Dado>}
        </dl>
        {f.observacao && <p className="whitespace-pre-wrap text-[var(--fg-2)]"><span className="text-[var(--fg-3)]">Observação: </span>{f.observacao}</p>}

        {canEdit && vivo && (
          <div className="flex flex-wrap gap-2">
            <button type="button" className={BTN} aria-expanded={painel === 'editar'} onClick={() => { setForm(formDaFicha(f)); abrir('editar'); }}>Editar ficha</button>
            <button type="button" className={BTN} aria-expanded={painel === 'nova'} onClick={() => { setNova(novaParcela(f, canVerDoc)); abrir('nova'); }}>Nova parcela</button>
            <button type="button" className={BTN} aria-expanded={painel === 'colar'} onClick={() => abrir('colar')}>Colar da planilha</button>
            <button type="button" className={BTN} aria-expanded={painel === 'arquivar'} onClick={() => abrir('arquivar')}>Arquivar</button>
            {podeDesfundir(f) && (
              <button type="button" className={BTN} aria-expanded={painel === 'desfundir'} onClick={() => abrir('desfundir')}>Desfazer fusão do sinal</button>
            )}
          </div>
        )}

        {canEdit && vivo && painel === 'editar' && (
          <form className="space-y-2 rounded-[var(--r-md)] border border-[var(--border)] p-2" aria-label="Editar ficha do contrato"
            onSubmit={(e) => { e.preventDefault(); salvar(); }}>
            <div className="grid grid-cols-2 gap-2 md:grid-cols-5">
              <Campo r="Valor cheio (R$)"><input type="text" inputMode="decimal" className={`${INPUT} w-full text-right tabular`} value={form.valor_bruto} onChange={(e) => setForm({ ...form, valor_bruto: e.target.value })} /></Campo>
              <Campo r="Valor líquido (R$)"><input type="text" inputMode="decimal" className={`${INPUT} w-full text-right tabular`} value={form.valor_liquido} onChange={(e) => setForm({ ...form, valor_liquido: e.target.value })} /></Campo>
              <Campo r="Assinado">
                <select className={`${INPUT} w-full`} value={form.assinado} onChange={(e) => setForm({ ...form, assinado: e.target.value as FormFichaContrato['assinado'] })}>
                  <option value="sim">Sim</option><option value="nao">Não</option><option value="indeterminado">Indeterminado</option>
                </select>
              </Campo>
              <Campo r="Data da assinatura"><input type="date" className={`${INPUT} w-full`} value={form.data_assinatura} onChange={(e) => setForm({ ...form, data_assinatura: e.target.value })} /></Campo>
              <Campo r="Link do contrato (Google Docs/Drive)"><input type="url" className={`${INPUT} w-full`} value={form.link_contrato} maxLength={500} spellCheck={false} autoComplete="off" onChange={(e) => setForm({ ...form, link_contrato: e.target.value })} /></Campo>
            </div>
            {erros.length > 0 && <ul role="alert" className="list-disc pl-5 text-[var(--red)]">{erros.map((x) => <li key={x}>{x}</li>)}</ul>}
            <div className="flex gap-2">
              <button type="submit" className={BTN_1} disabled={ocupado}>{ocupado ? 'Salvando…' : 'Salvar'}</button>
              <button type="button" className={BTN} onClick={() => setPainel(null)}>Cancelar</button>
            </div>
          </form>
        )}

        {canEdit && vivo && painel === 'arquivar' && (
          <Motivo titulo="Arquivar o contrato" explicacao="Arquiva a ficha e as parcelas ainda não baixadas; as baixadas ficam. Sem volta. O banco recusa se houver pagamento da Hotmart conciliado."
            motivo={motivo} onMotivo={setMotivo} ocupado={ocupado} confirmar="Confirmar arquivamento" onCancelar={() => setPainel(null)}
            onConfirmar={() => void executar(() => repo.salvarContratoHf({ id: f.id, arquivar_motivo: motivo.trim() }), () => setPainel(null))} />
        )}

        {canEdit && vivo && painel === 'desfundir' && f.transacao_sinal && (
          <Motivo titulo="Desfazer a fusão do sinal"
            explicacao={`Tira o sinal ${f.transacao_sinal} desta ficha e reabre a ficha criada por ele. As baixas automáticas que deixarem de casar são desfeitas na próxima sincronização (:25).`}
            motivo={motivo} onMotivo={setMotivo} ocupado={ocupado} confirmar="Confirmar: desfazer a fusão" onCancelar={() => setPainel(null)}
            onConfirmar={() => void executar(() => repo.desfundirContratoHf(f.id, motivo.trim()), () => setPainel(null))} />
        )}

        {canEdit && vivo && painel === 'nova' && (
          <FormularioInformado form={{ original: null, valores: nova.valores, erros: nova.erros }} canVerDoc={canVerDoc} ocupado={ocupado}
            tipoFixo
            onMudar={(valores) => setNova({ valores: { ...valores, tipo: TIPO_CONTRATO }, erros: [] })}
            onCancelar={() => setPainel(null)}
            onSalvar={() => {
              const r = entradaNovaParcela(nova.valores, f.id, canVerDoc);
              if (!r.entrada) { setNova({ ...nova, erros: r.erros }); return; }
              const entrada = r.entrada;
              const diferentes = nomesDiferentesDaFicha([entrada.cliente], f.nome);
              void (async () => {
                if (diferentes.length && !(await perguntar('formulario')(diferentes))) return;
                await executar(() => repo.salvarInformado(entrada), () => setPainel(null));
              })();
            }} />
        )}

        {confirmacao && (
          <ConfirmarNome origem={confirmacao.origem} nomes={confirmacao.nomes} nomeFicha={f.nome}
            onResponder={confirmacao.responder} />
        )}

        {canEdit && vivo && painel === 'colar' && (
          <ColarDaPlanilha repo={repoColar} canVerDoc={canVerDoc}
            onGravado={(n) => void executar(async () => ({ ok: true, msg: `${n} ${n === 1 ? 'parcela gravada' : 'parcelas gravadas'} neste contrato.` }), () => setPainel(null))} />
        )}

        <section className="space-y-1" aria-label="Parcelas do contrato">
          <p className="font-semibold text-[var(--fg)]">Parcelas <span className="font-normal text-[var(--fg-3)]">(as do período da grade e as sem data)</span></p>
          {parcelas.length === 0 ? <p className="text-[var(--fg-3)]">Nenhuma parcela no período.</p> : (
            <DataTable minWidth={720}>
              <Thead><Th>Parcela</Th><Th>Vencimento</Th><Th className="text-right">Valor</Th><Th>Situação</Th><Th>Observação</Th>{canEdit && <Th>Ações</Th>}</Thead>
              <tbody>
                {parcelas.map((p) => (
                  <LinhaParcela key={p.id} p={p} acoes={acoes} canEdit={canEdit && vivo} />
                ))}
              </tbody>
            </DataTable>
          )}
        </section>
      </div>
    </Drawer>
  );
}

function novaParcela(f: FichaContratoHF, canVerDoc: boolean): { valores: FormInformado; erros: string[] } {
  const v = formDeInformado(null, canVerDoc);
  return { valores: { ...v, tipo: TIPO_CONTRATO, cliente: f.nome ?? '', contrato_assinado: f.assinado === 'sim' ? 'S' : 'N' }, erros: [] };
}

function LinhaParcela({ p, acoes, canEdit }: { p: ParcelaContratoHF; acoes: AcoesParcela; canEdit: boolean }) {
  const sit = situacaoParcela(p);
  const aberta = acoes.acao?.id === p.id ? acoes.acao : null;
  const etapaPendente = p.situacao === 'a_receber_etapa';
  return (
    <Tr>
      <Td className="tabular text-xs whitespace-nowrap">{rotuloParcela(p)}</Td>
      <Td className="tabular text-xs whitespace-nowrap">
        {p.data_prevista ? fmtData(p.data_prevista) : <span className="text-[var(--fg-3)]">na etapa {p.etapa ?? '—'}</span>}
        {p.etapa && p.data_prevista && <span className="block text-[10px] text-[var(--fg-3)]">etapa {p.etapa}</span>}
      </Td>
      <Td className={`${NUM} text-xs`}>{fmtBRLc(p.valor)}</Td>
      <Td className="text-xs whitespace-nowrap">
        <span className={sit === 'em_atraso_cobrar' ? 'font-semibold text-[var(--red)]' : sit === 'baixado_hotmart' ? COR_HOTMART : sit === 'baixado_fora' ? COR_MANUAL : ''}>
          {ROTULO_SITUACAO[sit] ?? sit}
        </span>
        {p.baixa_manual_em && <span className="text-[var(--fg-3)]"> · {fmtData(p.baixa_manual_em)}</span>}
      </Td>
      <Td className="text-[11px] text-[var(--fg-2)]">{p.observacao ?? '—'}</Td>
      {canEdit && (
        <Td className="text-xs">
          {/* Baixa automática pela Hotmart: nenhuma ação (o banco recusa com P0001; estorno na Hotmart desfaz sozinho). */}
          {baixaPelaHotmart(p) ? <span className="text-[var(--fg-3)]">Baixa automática</span>
            : aberta ? (
              <ConfirmarData acao={aberta} acoes={acoes} rotulo={aberta.tipo === 'etapa' ? 'Etapa concluída em' : 'Dinheiro entrou em'}
                confirmar={aberta.tipo === 'etapa' ? 'Confirmar' : 'Confirmar baixa'} />
            ) : etapaPendente ? (
              <button type="button" className={BTN} disabled={acoes.ocupado} onClick={() => acoes.setAcao({ id: p.id, tipo: 'etapa', data: hojeISO() })}>Concluir etapa</button>
            ) : p.baixa_manual_em ? (
              <button type="button" className={BTN} disabled={acoes.ocupado} onClick={() => acoes.desfazerBaixa(p.id)}>Desfazer baixa</button>
            ) : (
              <button type="button" className={BTN} disabled={acoes.ocupado} onClick={() => acoes.setAcao({ id: p.id, tipo: 'baixar', data: hojeISO() })}>Baixar (Pix)</button>
            )}
        </Td>
      )}
    </Tr>
  );
}

/** Confirmação explícita, no fluxo da ficha (nada absolute): os dois nomes à vista. */
export function ConfirmarNome({ origem, nomes, nomeFicha, onResponder }: {
  origem: 'planilha' | 'formulario'; nomes: string[]; nomeFicha: string | null; onResponder: (ok: boolean) => void;
}) {
  const diz = nomes.map((n) => `"${n}"`).join(', ');
  return (
    <div role="alertdialog" aria-label="Confirmar o nome do cliente" className="space-y-2 rounded-[var(--r-md)] border border-[var(--yellow)] p-2">
      <p className="font-semibold text-[var(--fg)]">
        {origem === 'planilha' ? 'A planilha diz' : 'O formulário diz'} {diz}; esta ficha é de &quot;{nomeFicha ?? '—'}&quot;. Gravar nesta ficha mesmo assim?
      </p>
      <p className="text-[var(--fg-2)]">A parcela fica com o nome da ficha; o nome {origem === 'planilha' ? 'da planilha' : 'digitado'} vai para a observação.</p>
      <div className="flex gap-2">
        <button type="button" className={BTN_1} onClick={() => onResponder(true)}>Gravar nesta ficha</button>
        <button type="button" className={BTN} onClick={() => onResponder(false)}>Cancelar</button>
      </div>
    </div>
  );
}

function Dado({ r, children }: { r: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="text-[10px] uppercase text-[var(--fg-3)]">{r}</dt>
      <dd className="break-words text-[var(--fg)]">{children}</dd>
    </div>
  );
}

function Campo({ r, children }: { r: string; children: ReactNode }) {
  return <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]"><span>{r}</span>{children}</label>;
}

function Motivo({ titulo, explicacao, motivo, onMotivo, ocupado, confirmar, onConfirmar, onCancelar }: {
  titulo: string; explicacao: string; motivo: string; onMotivo: (m: string) => void; ocupado: boolean;
  confirmar: string; onConfirmar: () => void; onCancelar: () => void;
}) {
  return (
    <div className="space-y-2 rounded-[var(--r-md)] border border-[var(--border)] p-2" role="group" aria-label={titulo}>
      <p className="font-semibold text-[var(--fg)]">{titulo}</p>
      <p className="text-[var(--fg-2)]">{explicacao}</p>
      <label className="flex flex-wrap items-center gap-2 text-[var(--fg-2)]">
        Motivo (3 a 500 caracteres)
        <input type="text" className={`${INPUT} w-80`} value={motivo} maxLength={500} onChange={(e) => onMotivo(e.target.value)} />
      </label>
      <div className="flex gap-2">
        <button type="button" className={BTN_1} disabled={ocupado || !motivoValido(motivo)} onClick={onConfirmar}>{confirmar}</button>
        <button type="button" className={BTN} onClick={onCancelar}>Cancelar</button>
      </div>
    </div>
  );
}
