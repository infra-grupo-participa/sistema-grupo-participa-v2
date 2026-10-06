'use client';

// Peças da Mensageria usadas em mais de uma aba. Texto mínimo 14px (público não técnico).
// Vazio (null) = selo "não lançado", tracejado e com texto, para nunca ser lido como 0.
import { DataTable, EmptyState, Td, Th, Thead, Tr } from '@/shared/ui/components';
import {
  PENDENCIAS, ROTULO_TIPO, custoExibido, fmtCentavos, fmtNum, dataHoraSP, linhaDaApi, resumoCusto, rotuloCanal, rotuloFonte,
  rotuloPendencia,
  type Disparo, type Pendencia, type Totais, type TotalCanal, type TipoMensagem,
} from '../domain/mensageria';

/** Cabeçalho de tabela em 14px (o Th padrão é 11px em maiúsculas). */
export const thCls = '!text-sm !normal-case !tracking-normal';

export function Campo({ rotulo, dica, children }: { rotulo: string; dica?: string; children: React.ReactNode }) {
  return (
    <label className="block min-w-0">
      <span className="mb-1 block text-sm font-medium text-[var(--fg-2)]">
        {rotulo}{dica && <span className="font-normal"> · {dica}</span>}
      </span>
      {children}
    </label>
  );
}

export function Erro({ msg }: { msg: string | null | undefined }) {
  if (!msg) return null;
  return <p role="alert" className="text-sm text-[var(--red)]">{msg}</p>;
}

/** Erros de campo que o banco devolveu, como vieram. */
export function ErrosDoBanco({ erros }: { erros?: { campo: string; msg: string }[] }) {
  if (!erros || erros.length <= 1) return null;
  return (
    <ul className="mt-1 list-disc pl-5 text-sm text-[var(--red)]">
      {erros.map((e, i) => <li key={i}>{e.msg}</li>)}
    </ul>
  );
}

export function NaoLancado({ texto = 'não lançado' }: { texto?: string }) {
  return (
    <span className="inline-block whitespace-nowrap rounded-[var(--r-sm)] border border-dashed border-[var(--border-strong)] px-1.5 text-sm italic text-[var(--fg-2)]">
      {texto}
    </span>
  );
}

export function Num({ v }: { v: number | null | undefined }) {
  return v == null ? <NaoLancado /> : <span className="tabular">{fmtNum(v)}</span>;
}

export function Custo({ c }: { c: number | null | undefined }) {
  const t = fmtCentavos(c);
  return t == null ? <NaoLancado /> : <span className="tabular whitespace-nowrap">{t}</span>;
}

/** Selo neutro (texto + borda), para "estimado" e "automático · fonte". */
export function Selo({ children, title }: { children: React.ReactNode; title?: string }) {
  return (
    <span title={title} className="inline-block whitespace-nowrap rounded-[var(--r-sm)] border border-[var(--border-strong)] px-1.5 text-sm text-[var(--fg-2)]">
      {children}
    </span>
  );
}

/**
 * Custo de uma linha: real; só estimado = valor + selo "estimado"; sem preço = "sem preço" (nunca 0);
 * preço por entregue sem entregues lançado = "falta entregues".
 */
export function CustoLinha({ d }: { d: Disparo }) {
  const c = custoExibido(d);
  if (c.k === 'real') return <Custo c={c.c} />;
  if (c.k === 'estimado') {
    return (
      <span className="inline-flex flex-col items-start gap-0.5">
        <span className="tabular whitespace-nowrap">{fmtCentavos(c.c)}</span>
        <Selo title="Calculado pelo preço cadastrado. Lance o custo real para substituir.">estimado</Selo>
      </span>
    );
  }
  if (c.k === 'sem_preco') return <NaoLancado texto="sem preço" />;
  if (c.k === 'falta_entregues') return <NaoLancado texto="falta entregues" />;
  return <NaoLancado />;
}

/** Custo do período: total (real + estimado) e, embaixo, quanto dele é estimado. */
export function CustoPeriodo({ t }: { t: Pick<Totais, 'custo_centavos' | 'custo_estimado_centavos' | 'custo_total_centavos'> }) {
  const { total, estimado } = resumoCusto(t);
  return (
    <>
      <Custo c={total} />
      {total != null && estimado != null && estimado > 0 && (
        <div className="text-sm text-[var(--fg-2)]">{fmtCentavos(estimado)} estimado</div>
      )}
    </>
  );
}

export function SeloPendencia({ p }: { p: string }) {
  const alerta = p === 'conferir_zero_leitura';
  return (
    <span className={`inline-flex items-center gap-1.5 whitespace-nowrap rounded-[var(--r-sm)] border px-1.5 text-sm ${alerta ? 'border-[var(--red-border)] text-[var(--red)]' : 'border-[var(--yellow-border)] text-[var(--fg)]'}`}>
      <span aria-hidden className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ background: alerta ? 'var(--red)' : 'var(--yellow)' }} />
      {rotuloPendencia(p)}
    </span>
  );
}

/**
 * "Falta lançar": contagem das pendências do período inteiro (vem pronta do banco). Com `onEscolher`, cada item vira
 * botão que filtra a tabela abaixo (só as linhas carregadas). Pendência que o banco ainda não manda conta 0.
 */
export function FaltaLancar({ totais, escolhida, onEscolher }: {
  totais: Totais; escolhida?: Pendencia | null; onEscolher?: (p: Pendencia | null) => void;
}) {
  return (
    <section aria-label="Falta lançar" className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
      <h2 className="mb-2 text-sm font-semibold text-[var(--fg)]">
        Falta lançar <span className="font-normal text-[var(--fg-2)]">· no período{onEscolher ? ' · clique para ver as linhas' : ''}</span>
      </h2>
      <ul className="grid gap-2 sm:grid-cols-3 lg:grid-cols-5">
        {PENDENCIAS.map((p) => {
          const n = totais[p] ?? 0;
          const conteudo = (
            <>
              <span className={`text-lg font-bold tabular ${n > 0 ? 'text-[var(--fg)]' : 'text-[var(--fg-2)]'}`}>{fmtNum(n)}</span>
              {n > 0 ? <SeloPendencia p={p} /> : <span className="text-[var(--fg-2)]">{rotuloPendencia(p)}</span>}
            </>
          );
          return (
            <li key={p} className="text-sm">
              {onEscolher && n > 0 ? (
                <button
                  type="button"
                  aria-pressed={escolhida === p}
                  onClick={() => onEscolher(escolhida === p ? null : p)}
                  className={`flex items-baseline gap-2 rounded-[var(--r-sm)] px-1 text-left hover:underline ${escolhida === p ? 'outline outline-2 outline-[var(--accent)]' : ''}`}
                >
                  {conteudo}
                </button>
              ) : <div className="flex items-baseline gap-2 px-1">{conteudo}</div>}
            </li>
          );
        })}
      </ul>
    </section>
  );
}

/** Totais por canal do período inteiro (o banco soma; com 500 linhas de corte, somar aqui daria errado). */
export function TabelaPorCanal({ porCanal }: { porCanal: TotalCanal[] }) {
  if (porCanal.length === 0) return null;
  return (
    <DataTable minWidth={720}>
      <Thead>
        {['Canal', 'Disparos', 'Tamanho', 'Entregues', 'Lidas', 'Cliques', 'Falhas', 'Custo'].map((c) => <Th key={c} className={thCls}>{c}</Th>)}
      </Thead>
      <tbody>
        {porCanal.map((c) => (
          <Tr key={c.canal}>
            <Td className="whitespace-nowrap">{rotuloCanal(c.canal)}</Td>
            <Td><Num v={c.qtd} /></Td>
            <Td><Num v={c.tamanho} /></Td>
            <Td><Num v={c.entregues} /></Td>
            <Td><Num v={c.lidas} /></Td>
            <Td><Num v={c.cliques} /></Td>
            <Td><Num v={c.falhas} /></Td>
            <Td>
              <CustoPeriodo t={c} />
              {c.sem_custo > 0 && resumoCusto(c).total != null && (
                <div className="text-sm text-[var(--fg-2)]">{fmtNum(c.sem_custo)} sem custo</div>
              )}
            </Td>
          </Tr>
        ))}
      </tbody>
    </DataTable>
  );
}

/**
 * Coluna Ações presa à direita do container que rola na horizontal (o div overflow-x-auto do DataTable): com 15
 * colunas a tabela passa de 1.700px e, sem isso, "Lançar retorno" ficava fora da tela numa janela de 1280px, com a
 * barra de rolagem lá no fim da lista. Fundo opaco e sombra à esquerda (borda colapsada não acompanha o sticky).
 */
const acoesFixasTh = 'sticky right-0 z-[2] bg-[var(--surface-3)] shadow-[-1px_0_0_var(--border)]';
const acoesFixasTd = 'sticky right-0 z-[1] bg-[var(--surface-2)] shadow-[-1px_0_0_var(--border)]';

export function TabelaDisparos({ linhas, acoes, vazio = 'Nenhum disparo neste período' }: {
  linhas: Disparo[]; acoes?: (d: Disparo) => React.ReactNode; vazio?: string;
}) {
  if (linhas.length === 0) return <EmptyState title={vazio} />;
  const cols = ['Envio', 'Projeto', 'Canal', 'Ferramenta', 'Tipo', 'Copy', 'Público', 'Tamanho', 'Entregues', 'Lidas', 'Cliques', 'Falhas', 'Custo', 'Quem disparou', 'Pendências'];
  return (
    <DataTable minWidth={acoes ? 1900 : 1760}>
      <Thead>
        {cols.map((c) => <Th key={c} className={thCls}>{c}</Th>)}
        {acoes && <Th className={`${thCls} ${acoesFixasTh}`}>Ações</Th>}
      </Thead>
      <tbody>
        {linhas.map((d) => (
          <Tr key={d.id}>
            <Td>
              <div className="whitespace-nowrap tabular">{dataHoraSP(d.enviado_em)}</div>
              {linhaDaApi(d) && <Selo title="Veio pela integração. Aqui só mudam projeto, tipo e custo.">automático · {rotuloFonte(d.origem_sistema)}</Selo>}
            </Td>
            <Td>{d.projeto ? <span className="font-mono font-semibold">{d.projeto}</span> : <NaoLancado texto="sem projeto" />}</Td>
            <Td className="whitespace-nowrap">{rotuloCanal(d.canal)}</Td>
            <Td>
              <div className="whitespace-nowrap">{d.ferramenta}</div>
              {d.numero && <div className="whitespace-nowrap font-mono text-[var(--fg-2)]">{d.numero}</div>}
            </Td>
            <Td>{d.tipo ? (ROTULO_TIPO[d.tipo as TipoMensagem] ?? d.tipo) : <span className="text-[var(--fg-2)]" title="Só na API WhatsApp">—</span>}</Td>
            <Td className="max-w-[260px]">
              {d.campanha && <div className="line-clamp-2 break-words text-[var(--fg-2)]" title={d.campanha}>Campanha: {d.campanha}</div>}
              {d.copy_texto && <span className="line-clamp-2 break-words" title={d.copy_texto}>{d.copy_texto}</span>}
              {d.copy_link && (
                <a href={d.copy_link} target="_blank" rel="noopener noreferrer" className="block truncate text-[var(--accent)] underline" title={d.copy_link}>
                  Abrir link
                </a>
              )}
            </Td>
            <Td>
              <div className="whitespace-nowrap">{d.publico_lista}</div>
              {d.publico_origem && <div className="whitespace-nowrap text-[var(--fg-2)]">{d.publico_origem}</div>}
            </Td>
            <Td><Num v={d.tamanho_lista} /></Td>
            <Td><Num v={d.entregues} /></Td>
            <Td><Num v={d.lidas} /></Td>
            <Td><Num v={d.cliques} /></Td>
            <Td><Num v={d.falhas} /></Td>
            <Td><CustoLinha d={d} /></Td>
            <Td className="whitespace-nowrap">{d.disparado_por}</Td>
            <Td>
              {d.pendencias.length === 0
                ? <span className="text-sm text-[var(--fg-2)]">—</span>
                : <div className="flex flex-col items-start gap-1">{d.pendencias.map((p) => <SeloPendencia key={p} p={p} />)}</div>}
            </Td>
            {acoes && <Td className={`whitespace-nowrap ${acoesFixasTd}`}>{acoes(d)}</Td>}
          </Tr>
        ))}
      </tbody>
    </DataTable>
  );
}
