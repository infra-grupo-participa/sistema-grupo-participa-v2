'use client';

// Visão geral do Contas a Receber (#visao, fatia F4). Responde, de cima para baixo: quanto entra nas próximas 4 semanas
// e quanto disso é certo; o que pede ação (alertas); o que mudou desde a última foto; e se a previsão acertou.
// Sem consulta própria: o pai (FinanceiroClient) carrega e guarda tudo — a carga base da grade (reusada se já estiver
// em memória), as fotos da z69 e a lista de eventos (a mesma da sub-aba Eventos). Este componente só desenha.
// Todo número clicável é um link de hash para a sub-aba que mostra aquele número (filtrada, quando há filtro).
import { useState, type ReactNode } from 'react';
import { Icon } from '@/shared/ui/icons';
import { fmtBRLc, fmtDataHora } from '@/shared/ui/format';
import type { ContasReceberCarregado } from '../../application/carregar-contas-receber';
import { hojeSaoPaulo } from '../../application/carregar-contas-receber';
import type { VisaoReceberCarregada } from '../../application/carregar-visao-receber';
import type { EventoPlanejado } from '../../domain/eventos-planejados';
import {
  alertasReceber, fotosBase, primeiraSemanaComparavel, proximaFoto, proximas4Semanas, resumirPrevistoRealizado,
  separarMudancas, type LinhaPrevistoRealizado, type MotivoItem, type MudancaReceber, type SemanaPrevistoRealizado,
} from '../../domain/visao-receber';
import { rotuloBloco } from './rotulos-receber';
import { hashDaSubAbaReceber, hashReceberFiltrado } from './hash';
import { SUBABAS_RECEBER, VISAO_GERAL as T } from './textos';

const TH = 'px-2 py-1.5 text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';
const TD = 'px-2 py-1 whitespace-nowrap';
const TD_NUM = 'px-2 py-1 text-right tabular whitespace-nowrap';
const LINK = 'underline decoration-dotted underline-offset-2 hover:text-[var(--accent)]';

const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
const periodo = (de: string, ate: string) => (de === ate ? ddmm(de) : `${ddmm(de)}–${ddmm(ate)}`);
const sinal = (v: number) => (Math.round(v * 100) > 0 ? `+${fmtBRLc(v)}` : fmtBRLc(v));
const pct = (fracao: number | null) =>
  fracao == null ? '—' : `${(Math.round(fracao * 1000) / 10).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
const pctPronto = (v: number | null) => (v == null ? '—' : `${v.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`);

/** Hoje e minuto do dia em São Paulo (a foto é segunda 06:11 em São Paulo, não no fuso do navegador). */
function agoraSaoPaulo(agora: Date): { hoje: string; minutos: number } {
  const p = new Intl.DateTimeFormat('en-GB', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit', hour12: false })
    .formatToParts(agora);
  const h = Number(p.find((x) => x.type === 'hour')?.value ?? 0) % 24;
  const m = Number(p.find((x) => x.type === 'minute')?.value ?? 0);
  return { hoje: hojeSaoPaulo(agora), minutos: h * 60 + m };
}

function Secao({ id, titulo, children, extra }: { id: string; titulo: string; children: ReactNode; extra?: ReactNode }) {
  return (
    <section aria-labelledby={id} className="rounded-[var(--r-md)] border border-[var(--border)]">
      <div className="flex flex-wrap items-baseline gap-x-3 border-b border-[var(--border)] px-2 py-1">
        <h2 id={id} className="text-[11px] font-semibold uppercase text-[var(--fg-2)]">{titulo}</h2>
        {extra}
      </div>
      <div className="p-2">{children}</div>
    </section>
  );
}

function Status({ children }: { children: ReactNode }) {
  return <p role="status" className="text-xs text-[var(--fg-3)]">{children}</p>;
}

function Erro({ msg, onTentar }: { msg: string; onTentar?: () => void }) {
  return (
    <p role="alert" className="flex flex-wrap items-center gap-2 text-xs text-[var(--fg)]">
      <Icon name="alert" size={13} className="text-[var(--red)]" /> {msg}
      {onTentar && (
        <button type="button" onClick={onTentar} className="rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 font-semibold hover:bg-[var(--surface-2)]">
          {T.tentarDeNovo}
        </button>
      )}
    </p>
  );
}

/** Valor que leva à grade (Semana a semana). Zero não é link (não parece clicável) e não é pintado. */
function ValorGrade({ v, rotulo, per }: { v: number; rotulo: string; per: string }) {
  if (Math.round(v * 100) === 0) return <span className="text-[var(--fg-4)]">–</span>;
  return (
    <a href={hashDaSubAbaReceber('semana')} className={LINK} aria-label={T.abrirGrade(rotulo, per, fmtBRLc(v))}>{fmtBRLc(v)}</a>
  );
}

// ─── (a) Próximas 4 semanas ─────────────────────────────────────────────────
function QuatroSemanas({ dados, projecaoDesligada }: { dados: ContasReceberCarregado; projecaoDesligada: boolean }) {
  const q = proximas4Semanas(dados.linhas, dados.hojeISO);
  const linhas: { k: 'certo' | 'estimado' | 'total'; l: string }[] = [
    { k: 'certo', l: T.certo }, { k: 'estimado', l: T.estimado }, { k: 'total', l: T.total },
  ];
  const rotuloTotal = `${T.quatroSemanas} (${periodo(q.semanas[0].inicio, q.semanas[3].fim)})`;
  return (
    <>
      {dados.desligado && <p role="alert" className="mb-2 text-xs font-semibold text-[var(--fg)]">{T.recebimentoDesligado}</p>}
      <div className="overflow-x-auto">
        <table className="w-full border-collapse text-xs">
          <caption className="sr-only">{T.semanasCaption}</caption>
          <thead>
            <tr>
              <th scope="col" className={`${TH} text-left`}><span className="sr-only">{T.linha}</span></th>
              {q.semanas.map((s) => <th key={s.inicio} scope="col" className={`${TH} text-right`}>{periodo(s.inicio, s.fim)}</th>)}
              <th scope="col" className={`${TH} border-l border-[var(--border)] text-right`}>{T.quatroSemanas}</th>
            </tr>
          </thead>
          <tbody>
            {linhas.map(({ k, l }) => (
              <tr key={k} className={`border-t border-[var(--border-faint)] ${k === 'total' ? 'font-semibold' : ''}`}>
                <th scope="row" className={`${TD} text-left ${k === 'total' ? 'text-[var(--fg)]' : 'text-[var(--fg-2)]'}`}>{l}</th>
                {k === 'estimado' && projecaoDesligada ? (
                  <td colSpan={5} className={`${TD} text-right text-[var(--fg-3)]`}>{T.estimadoDesligado}</td>
                ) : (
                  <>
                    {q.semanas.map((s) => (
                      <td key={s.inicio} className={TD_NUM}><ValorGrade v={s[k]} rotulo={l} per={periodo(s.inicio, s.fim)} /></td>
                    ))}
                    <td className={`${TD_NUM} border-l border-[var(--border)]`}><ValorGrade v={q[k]} rotulo={l} per={rotuloTotal} /></td>
                  </>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

// ─── (d) Alertas ────────────────────────────────────────────────────────────
function LinhaAlerta({ ativo, rotulo, children }: { ativo: boolean; rotulo: string; children: ReactNode }) {
  // Cor só no que pede ação, e nunca sozinha: ícone + texto. Zero fica neutro (não é alarme).
  return (
    <li className="flex items-baseline gap-2 border-t border-[var(--border-faint)] py-1 first:border-t-0">
      <span className="w-4 shrink-0" aria-hidden="true">
        {ativo && <Icon name="alert" size={12} className="text-[var(--yellow)]" />}
      </span>
      <span className={`min-w-0 flex-1 ${ativo ? 'font-semibold text-[var(--fg)]' : 'text-[var(--fg-2)]'}`}>{rotulo}</span>
      <span className="text-right tabular">{children}</span>
    </li>
  );
}

function Alertas({ dados, eventos, erroEventos, projecaoDesligada }: {
  dados: ContasReceberCarregado; eventos: EventoPlanejado[] | null; erroEventos: string | null; projecaoDesligada: boolean;
}) {
  const a = alertasReceber(dados.linhas, dados.recorrencias);
  const encerrados = eventos?.filter((e) => e.situacao === 'encerrado').length ?? 0;
  const ir = (href: string, texto: string, onde: string) => (
    <a href={href} className={LINK} aria-label={`${texto}, ${T.verEm(onde)}`}>{texto}</a>
  );
  return (
    <ul className="text-xs">
      <LinhaAlerta ativo={a.foraDaProjecao.n > 0} rotulo={T.foraDaProjecao}>
        {a.foraDaProjecao.n === 0 ? <span className="text-[var(--fg-3)]">{T.nenhuma}</span>
          : ir(hashReceberFiltrado('recorrencias', 'em_atraso_fora'),
            `${T.cobrancas(a.foraDaProjecao.n)} · ${fmtBRLc(a.foraDaProjecao.valor)}`, SUBABAS_RECEBER.recorrencias)}
      </LinhaAlerta>
      <LinhaAlerta ativo={a.informadosACobrar.n > 0} rotulo={T.informadosACobrar}>
        {a.informadosACobrar.n === 0 ? <span className="text-[var(--fg-3)]">{T.nenhum}</span>
          : ir(hashReceberFiltrado('informados', 'em_atraso_cobrar'),
            `${T.informados(a.informadosACobrar.n)} · ${fmtBRLc(a.informadosACobrar.valor)}`, SUBABAS_RECEBER.informados)}
      </LinhaAlerta>
      <LinhaAlerta ativo={a.semBase.length > 0} rotulo={T.semBase}>
        {a.semBase.length === 0 ? <span className="text-[var(--fg-3)]">{T.nenhum}</span>
          : ir(hashDaSubAbaReceber('premissas'),
            `${T.grupos(a.semBase.length)}: ${a.semBase.map((x) => x.grupo).join(', ')}`, SUBABAS_RECEBER.premissas)}
      </LinhaAlerta>
      <LinhaAlerta ativo={encerrados > 0} rotulo={T.eventosEncerrados}>
        {erroEventos ? <span className="text-[var(--fg-2)]">{T.eventosErro}</span>
          : eventos == null ? <span className="text-[var(--fg-3)]">{T.eventosCarregando}</span>
          : encerrados === 0 ? <span className="text-[var(--fg-3)]">{T.nenhum}</span>
          : ir(hashReceberFiltrado('eventos', 'encerrado'), T.eventos(encerrados), SUBABAS_RECEBER.eventos)}
      </LinhaAlerta>
      <LinhaAlerta ativo={projecaoDesligada} rotulo={T.projecao}>
        {projecaoDesligada ? ir(hashDaSubAbaReceber('premissas'), T.projecaoDesligada, SUBABAS_RECEBER.premissas)
          : <span className="text-[var(--fg-3)]">{T.projecaoLigada}</span>}
      </LinhaAlerta>
    </ul>
  );
}

// ─── (b) O que mudou ────────────────────────────────────────────────────────
function textoMotivo(m: MotivoItem): string {
  return `${T.motivos[m.motivo] ?? m.motivo}: ${T.itens(m.itens)} (${sinal(m.valor)})`;
}

function Motivos({ x }: { x: MudancaReceber }) {
  return (
    <ul className="space-y-0.5">
      {x.motivos.map((m) => {
        const t = textoMotivo(m);
        // Saiu por atraso: leva à lista de quem saiu (bloco 2 → Recorrências; bloco 5 → Informados a cobrar).
        const href = m.motivo === 'saiu_atraso'
          ? x.bloco === 2 ? hashReceberFiltrado('recorrencias', 'em_atraso_fora')
            : x.bloco === 5 ? hashReceberFiltrado('informados', 'em_atraso_cobrar') : null
          : null;
        return <li key={m.motivo}>{href ? <a href={href} className={LINK}>{t}</a> : t}</li>;
      })}
    </ul>
  );
}

function OQueMudou({ visao, onTentar, agora }: { visao: VisaoReceberCarregada; onTentar: () => void; agora: Date }) {
  if (visao.fotos.erro != null) return <Erro msg={visao.fotos.erro} onTentar={onTentar} />;
  const base = fotosBase(visao.fotos.dados);
  const { hoje, minutos } = agoraSaoPaulo(agora);
  const proxima = ddmm(proximaFoto(hoje, minutos));
  if (base.length === 0) return <p className="text-xs text-[var(--fg-2)]">{T.semFoto(proxima)}</p>;
  if (!visao.comparacao) {
    const f = base[0];
    return (
      <p className="text-xs text-[var(--fg-2)]">
        {T.umaFoto(`${fmtDataHora(f.foto_em)}${f.reconstruida ? `, ${T.fotoReconstruida}` : ''}`, proxima)}
      </p>
    );
  }
  const { anterior, recente } = visao.comparacao;
  const m = visao.mudancas;
  return (
    <div className="space-y-2">
      <p className="text-xs text-[var(--fg-2)]">
        <span className="font-semibold text-[var(--fg)]">{T.comparando(fmtDataHora(anterior.foto_em), fmtDataHora(recente.foto_em))}</span>
        {' · '}{T.somaFotos(fmtBRLc(anterior.soma_a_receber), fmtBRLc(recente.soma_a_receber), sinal(recente.soma_a_receber - anterior.soma_a_receber))}
        {(anterior.reconstruida || recente.reconstruida) && ` · ${T.fotoReconstruida}`}
      </p>
      {m == null ? <Status>{T.carregandoMudancas}</Status>
        : m.erro != null ? <Erro msg={m.erro} onTentar={onTentar} />
        : <TabelaMudancas mudancas={m.dados} />}
    </div>
  );
}

function TabelaMudancas({ mudancas }: { mudancas: MudancaReceber[] }) {
  const { mudaram, semMudanca } = separarMudancas(mudancas);
  if (mudaram.length === 0) return <p className="text-xs text-[var(--fg-2)]">{T.nadaMudou}</p>;
  return (
    <>
      <div className="overflow-x-auto">
        <table className="w-full border-collapse text-xs">
          <caption className="sr-only">{T.mudouCaption}</caption>
          <thead>
            <tr>
              <th scope="col" className={`${TH} text-left`}>{T.grupo}</th>
              <th scope="col" className={`${TH} text-right`}>{T.antes}</th>
              <th scope="col" className={`${TH} text-right`}>{T.agora}</th>
              <th scope="col" className={`${TH} text-right`}>{T.diferenca}</th>
              <th scope="col" className={`${TH} text-left`}>{T.porque}</th>
            </tr>
          </thead>
          <tbody>
            {mudaram.map((x) => (
              <tr key={`${x.bloco}-${x.grupo}`} className="border-t border-[var(--border-faint)] align-top text-[var(--fg)]">
                <th scope="row" className={`${TD} text-left font-normal`}>
                  <span className="text-[var(--fg-3)]">{x.bloco}. {rotuloBloco(x.bloco)} · </span>{x.grupo}
                </th>
                <td className={`${TD_NUM} text-[var(--fg-2)]`}>{fmtBRLc(x.valor_a)}</td>
                <td className={TD_NUM}>
                  {Math.round(x.valor_b * 100) === 0 ? fmtBRLc(0)
                    : <a href={hashDaSubAbaReceber('semana')} className={LINK} aria-label={T.abrirGrade(x.grupo, T.agora, fmtBRLc(x.valor_b))}>{fmtBRLc(x.valor_b)}</a>}
                </td>
                <td className={`${TD_NUM} font-semibold`}>{sinal(x.delta)}</td>
                <td className="px-2 py-1 text-[var(--fg-2)]"><Motivos x={x} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {semMudanca > 0 && <p className="text-xs text-[var(--fg-3)]">{T.semMudanca(semMudanca)}</p>}
    </>
  );
}

// ─── (c) Previsão × realizado ───────────────────────────────────────────────
function DetalheSemana({ s }: { s: SemanaPrevistoRealizado }) {
  const nome = (l: LinhaPrevistoRealizado) => (l.bloco == null ? (l.grupo ?? T.foraDaFotoGrupo) : `${l.bloco}. ${rotuloBloco(l.bloco)} · ${l.grupo ?? ''}`);
  return (
    <table className="w-full border-collapse text-xs">
      <caption className="sr-only">{T.detalheCaption(periodo(s.de, s.ate))}</caption>
      <thead>
        <tr>
          <th scope="col" className={`${TH} text-left`}>{T.grupo}</th>
          <th scope="col" className={`${TH} text-right`}>{T.previsto}</th>
          <th scope="col" className={`${TH} text-right`}>{T.realizado}</th>
          <th scope="col" className={`${TH} text-right`}>{T.desvio}</th>
          <th scope="col" className={`${TH} text-right`}>{T.acerto}</th>
        </tr>
      </thead>
      <tbody>
        {s.linhas.map((l, i) => (
          <tr key={`${l.bloco ?? 'x'}-${l.grupo ?? i}`} className="border-t border-[var(--border-faint)] text-[var(--fg)]">
            <th scope="row" className={`${TD} text-left font-normal`}>{nome(l)}</th>
            <td className={TD_NUM}>{l.previsto == null ? '—' : fmtBRLc(l.previsto)}</td>
            <td className={TD_NUM}>{l.realizado == null ? <span className="text-[var(--fg-3)]">{T.naoMedido}</span> : fmtBRLc(l.realizado)}</td>
            <td className={TD_NUM}>{l.desvio == null || l.realizado == null ? '—' : sinal(l.desvio)}</td>
            <td className={TD_NUM}>{pctPronto(l.acerto_pct)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function PrevistoRealizado({ visao, onTentar }: { visao: VisaoReceberCarregada; onTentar: () => void }) {
  const [aberta, setAberta] = useState<string | null>(null);
  if (visao.previsto.erro != null) return <Erro msg={visao.previsto.erro} onTentar={onTentar} />;
  const r = resumirPrevistoRealizado(visao.previsto.dados);
  const primeira = visao.fotos.dados ? primeiraSemanaComparavel(visao.fotos.dados) : null;
  return (
    <div className="space-y-3">
      {r.semanas.length === 0 ? (
        <p className="text-xs text-[var(--fg-2)]">
          {primeira ? T.nenhumaSemana(ddmm(primeira.de), ddmm(primeira.ate), ddmm(primeira.sai)) : T.semanasSemFoto(r.semanasSemFoto)}
        </p>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-xs">
              <caption className="sr-only">{T.prCaption}</caption>
              <thead>
                <tr>
                  <th scope="col" className={`${TH} text-left`}>{T.semana}</th>
                  <th scope="col" className={`${TH} text-right`}>{T.certoPrevisto}</th>
                  <th scope="col" className={`${TH} text-right`}>{T.certoRealizado}</th>
                  <th scope="col" className={`${TH} text-right`}>{T.acerto}</th>
                  <th scope="col" className={`${TH} text-right`}>{T.estimadoPrevisto}</th>
                  <th scope="col" className={`${TH} text-right`}>{T.foraDaFoto}</th>
                  <th scope="col" className={TH}><span className="sr-only">{T.detalhar}</span></th>
                </tr>
              </thead>
              <tbody>
                {r.semanas.map((s) => {
                  const idDet = `visao-pr-${s.de}`;
                  const aqui = aberta === s.de;
                  return [
                    <tr key={s.de} className="border-t border-[var(--border-faint)] text-[var(--fg)]">
                      <th scope="row" className={`${TD} text-left font-normal`}>
                        {periodo(s.de, s.ate)}
                        {s.notas.length > 0 && <span className="block text-[10px] text-[var(--fg-3)]">{s.notas.join(' · ')}</span>}
                      </th>
                      <td className={TD_NUM}>{fmtBRLc(s.certoPrevisto)}</td>
                      <td className={TD_NUM}>{fmtBRLc(s.certoRealizado)}</td>
                      <td className={`${TD_NUM} font-semibold`}>{pctPronto(s.certoAcerto)}</td>
                      <td className={TD_NUM}>{fmtBRLc(s.estimadoPrevisto)}</td>
                      <td className={TD_NUM}>{fmtBRLc(s.foraDaFoto)}</td>
                      <td className={TD}>
                        <button type="button" aria-expanded={aqui} aria-controls={idDet} onClick={() => setAberta(aqui ? null : s.de)}
                          className="rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-[var(--fg-2)] hover:bg-[var(--surface-2)]">
                          {aqui ? T.fechar : T.detalhar}
                        </button>
                      </td>
                    </tr>,
                    aqui && (
                      <tr key={`${s.de}-d`} id={idDet}>
                        <td colSpan={7} className="bg-[var(--surface-2)] px-2 py-2"><DetalheSemana s={s} /></td>
                      </tr>
                    ),
                  ];
                })}
              </tbody>
            </table>
          </div>
          {r.semanasSemFoto > 0 && <p className="text-xs text-[var(--fg-3)]">{T.semanasSemFoto(r.semanasSemFoto)}</p>}
        </>
      )}
      <Perda perda={r.perda} />
    </div>
  );
}

function Perda({ perda }: { perda: LinhaPrevistoRealizado[] }) {
  return (
    <div className="space-y-1">
      <h3 className="text-[11px] font-semibold uppercase text-[var(--fg-2)]">{T.perdaTitulo}</h3>
      {perda.length === 0 ? <p className="text-xs text-[var(--fg-2)]">{T.perdaVazia}</p> : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-xs">
            <caption className="sr-only">{T.perdaCaption}</caption>
            <thead>
              <tr>
                <th scope="col" className={`${TH} text-left`}>{T.grupo}</th>
                <th scope="col" className={`${TH} text-right`}>{T.perdaMedida}</th>
                <th scope="col" className={`${TH} text-right`}>{T.premissaEmUso}</th>
                <th scope="col" className={`${TH} text-right`}>{T.resolvidas}</th>
                <th scope="col" className={`${TH} text-right`}>{T.perdidas}</th>
                <th scope="col" className={`${TH} text-right`}>{T.valorPerdido}</th>
                <th scope="col" className={TH}><span className="sr-only">{T.ajustar}</span></th>
              </tr>
            </thead>
            <tbody>
              {perda.map((p) => (
                <tr key={p.grupo ?? ''} className="border-t border-[var(--border-faint)] text-[var(--fg)]">
                  <th scope="row" className={`${TD} text-left font-normal`}>{p.grupo}</th>
                  <td className={`${TD_NUM} font-semibold`}>{p.perda_medida == null ? T.semResolvidas : pct(p.perda_medida)}</td>
                  <td className={TD_NUM}>{pct(p.premissa_atual)}</td>
                  <td className={TD_NUM}>{p.cobrancas_resolvidas ?? 0}</td>
                  <td className={TD_NUM}>{p.cobrancas_perdidas ?? 0}</td>
                  <td className={TD_NUM}>{fmtBRLc(p.valor_perdido)} / {fmtBRLc(p.valor_resolvido)}</td>
                  <td className={TD}>
                    <a href={hashDaSubAbaReceber('premissas')} className={LINK} aria-label={T.ajustarGrupo(p.grupo ?? '')}>{T.ajustar}</a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

// ─── A tela ─────────────────────────────────────────────────────────────────
export function VisaoGeral({
  dados, erroReceber, onTentarReceber, visao, onTentarVisao, eventos, erroEventos, agora,
}: {
  /** Carga do cenário base (a mesma da grade). NULL = carregando. */
  dados: ContasReceberCarregado | null;
  erroReceber: string | null;
  onTentarReceber: () => void;
  /** Fotos, o que mudou e previsto × realizado. NULL = carregando. */
  visao: VisaoReceberCarregada | null;
  onTentarVisao: () => void;
  /** Lista de eventos planejados (a mesma da sub-aba Eventos). NULL = carregando. */
  eventos: EventoPlanejado[] | null;
  erroEventos: string | null;
  /** Relógio (teste). Padrão: agora. */
  agora?: Date;
}) {
  const [relogio] = useState(() => agora ?? new Date());
  const projecaoDesligada = dados ? alertasReceber(dados.linhas, dados.recorrencias).projecaoDesligada : false;
  // Sem a carga base: o erro (com "tentar de novo") aparece uma vez, nas 4 semanas; os alertas dizem de onde dependem.
  // Carga base em memória vence um erro de OUTRO cenário (o erro da aba é um só no pai).
  const semBase = dados ? null : erroReceber ? <Erro msg={erroReceber} onTentar={onTentarReceber} />
    : <Status>{T.carregandoPrevisao}</Status>;
  return (
    <div className="space-y-3">
      <div className="grid gap-3 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <Secao id="visao-semanas" titulo={T.semanasTitulo}>
          {semBase ?? <QuatroSemanas dados={dados!} projecaoDesligada={projecaoDesligada} />}
        </Secao>
        <Secao id="visao-alertas" titulo={T.alertasTitulo}>
          {dados ? <Alertas dados={dados} eventos={eventos} erroEventos={erroEventos} projecaoDesligada={projecaoDesligada} />
            : erroReceber ? <p className="text-xs text-[var(--fg-2)]">{T.alertasSemPrevisao}</p>
            : <Status>{T.carregandoPrevisao}</Status>}
        </Secao>
      </div>
      <Secao id="visao-mudou" titulo={T.mudouTitulo}>
        {!visao ? <Status>{T.carregandoMudancas}</Status> : <OQueMudou visao={visao} onTentar={onTentarVisao} agora={relogio} />}
      </Secao>
      <Secao id="visao-pr" titulo={T.prTitulo}>
        {!visao ? <Status>{T.carregandoPr}</Status> : <PrevistoRealizado visao={visao} onTentar={onTentarVisao} />}
      </Secao>
    </div>
  );
}
