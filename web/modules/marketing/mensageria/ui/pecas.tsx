'use client';

// Peças da Mensageria usadas em mais de uma aba. Texto mínimo 14px (público não técnico).
// Vazio (null) = selo "não lançado", tracejado e com texto, para nunca ser lido como 0.
import { Button, DataTable, Td, Th, Thead, Tr } from '@/shared/ui/components';
import {
  PENDENCIAS, ROTULO_TIPO, custoExibido, fmtCentavos, fmtNum, dataHoraSP, linhaDaApi, resumoCusto, rotuloCanal, rotuloFonte,
  rotuloPendencia,
  type Disparo, type Pendencia, type Totais, type TotalCanal, type TipoMensagem,
} from '../domain/mensageria';

/**
 * Cabeçalho de tabela em 14px (o Th padrão é 11px em maiúsculas) e em --fg-2: o --fg-3 do Thead sobre --surface-3
 * dá 3,8:1 no escuro (reprova AA). Coluna de número alinha à direita (`thNum` no Th, `tdNum` no Td).
 */
export const thCls = '!text-sm !normal-case !tracking-normal text-[var(--fg-2)]';
export const thNum = `${thCls} !text-right`;
export const tdNum = 'text-right tabular';

/**
 * Cores de texto derivadas do tema (sem hex): --red puro sobre --surface-2 dá 4,2:1 no escuro e o --accent dá 2,9:1
 * sobre branco no claro, os dois abaixo do AA (4,5:1). Misturar com --fg puxa para o lado legível nos 2 temas.
 */
export const corAlerta = 'text-[color-mix(in_srgb,var(--red)_70%,var(--fg))]';
export const corLink = 'text-[color-mix(in_srgb,var(--accent)_60%,var(--fg))]';

/** Botão-texto das tabelas: cor AA nos 2 temas e 44px de altura (alvo de toque). */
export function BotaoLink({ className = '', ...rest }: React.ComponentProps<typeof Button>) {
  return <Button variant="link" className={`!text-[color-mix(in_srgb,var(--accent)_60%,var(--fg))] min-h-11 underline-offset-2 ${className}`} {...rest} />;
}

/** Botão de topo de aba com 44px de altura (alvo de toque). */
export const botaoTopo = 'min-h-11';

/** Estado vazio: frase curta + o que fazer, em 16px. Sem ícone (enfeite). */
export function Vazio({ titulo, dica }: { titulo: string; dica?: string }) {
  return (
    <div role="status" className="rounded-[var(--r-lg)] border border-dashed border-[var(--border-strong)] px-4 py-6 text-center">
      <p className="text-base font-medium text-[var(--fg)]">{titulo}</p>
      {dica && <p className="mt-1 text-sm text-[var(--fg-2)]">{dica}</p>}
    </div>
  );
}

/** Falha de carga (rede ou sem acesso): diz o que não veio e o que fazer. */
export function ErroCarga({ oque }: { oque: string }) {
  return (
    <p role="alert" className={`rounded-[var(--r-md)] border border-[var(--red-border)] px-3 py-2 text-base ${corAlerta}`}>
      Não foi possível carregar {oque}. Recarregue a página; se continuar, fale com a equipe técnica.
    </p>
  );
}

/** Aviso em faixa (nota explicativa ou corte de período). */
export function Faixa({ children, tom = 'nota' }: { children: React.ReactNode; tom?: 'nota' | 'aviso' | 'filtro' }) {
  const borda = tom === 'aviso' ? 'border-[var(--yellow-border-forte)]' : tom === 'filtro' ? 'border-[var(--accent)]' : 'border-[var(--border)]';
  return (
    <p role={tom === 'nota' ? 'note' : 'status'} className={`flex flex-wrap items-center gap-x-2 rounded-[var(--r-md)] border ${borda} px-3 py-2 text-sm text-[var(--fg)]`}>
      {children}
    </p>
  );
}

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
  return <p role="alert" className={`text-sm ${corAlerta}`}>{msg}</p>;
}

/** Erros de campo que o banco devolveu, como vieram. */
export function ErrosDoBanco({ erros }: { erros?: { campo: string; msg: string }[] }) {
  if (!erros || erros.length <= 1) return null;
  return (
    <ul className={`mt-1 list-disc pl-5 text-sm ${corAlerta}`}>
      {erros.map((e, i) => <li key={i}>{e.msg}</li>)}
    </ul>
  );
}

export function NaoLancado({ texto = 'não lançado' }: { texto?: string }) {
  return (
    <span className="inline-block whitespace-nowrap rounded-[var(--r-sm)] border border-dashed border-[var(--border-strong)] px-1.5 text-sm italic leading-6 text-[var(--fg-2)]">
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

/**
 * Selo único da área (mesma forma do Badge do design system: chip neutro, cor só no ponto), em 14px.
 * neutro = informação (automático, estimado) · ok = ligado/ativo/em vigor · aviso = falta algo · alerta = conferir ·
 * apagado = desligado/arquivado/substituído. O texto sempre diz o estado (nunca só a cor).
 */
export type TomSelo = 'neutro' | 'ok' | 'aviso' | 'alerta' | 'apagado';
const PONTO: Record<Exclude<TomSelo, 'neutro'>, string> = {
  ok: 'var(--green)', aviso: 'var(--yellow)', alerta: 'var(--red)', apagado: 'var(--fg-3)',
};
export function Selo({ children, title, tom = 'neutro' }: { children: React.ReactNode; title?: string; tom?: TomSelo }) {
  const cor = tom === 'alerta' ? corAlerta : tom === 'aviso' ? 'text-[var(--fg)]' : 'text-[var(--fg-2)]';
  return (
    <span title={title} className={`inline-flex max-w-full items-center gap-1.5 whitespace-nowrap rounded-[var(--r-sm)] border border-[var(--border-strong)] bg-[var(--surface-3)] px-1.5 text-sm leading-6 ${cor}`}>
      {tom !== 'neutro' && <span aria-hidden className="h-2 w-2 shrink-0 rounded-full" style={{ background: PONTO[tom] }} />}
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
      <span className="inline-flex flex-col items-end gap-0.5">
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

export const tomPendencia = (p: string): 'alerta' | 'aviso' => (p === 'conferir_zero_leitura' ? 'alerta' : 'aviso');

export function SeloPendencia({ p }: { p: string }) {
  return <Selo tom={tomPendencia(p)}>{rotuloPendencia(p)}</Selo>;
}

/** Quadro de número: rótulo curto em cima, número grande, nota em cor suave. Mesma moldura em "Falta lançar". */
const quadroCls = 'flex h-full w-full min-w-0 flex-col items-start gap-0.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2 text-left';

export function Quadro({ rotulo, valor, nota }: { rotulo: React.ReactNode; valor: React.ReactNode; nota?: React.ReactNode }) {
  return (
    <div className={quadroCls}>
      <div className="text-sm text-[var(--fg-2)]">{rotulo}</div>
      <div className="max-w-full break-words text-2xl font-bold leading-tight tabular text-[var(--fg)]">{valor}</div>
      {nota && <div className="text-sm text-[var(--fg-2)]">{nota}</div>}
    </div>
  );
}

/** Título de bloco: rótulo pequeno em maiúsculas, cinza, e complemento ao lado. */
export function TituloBloco({ id, children, extra }: { id?: string; children: React.ReactNode; extra?: React.ReactNode }) {
  return (
    <div className="mb-2 flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
      <h2 id={id} className="text-sm font-semibold uppercase tracking-wide text-[var(--fg-2)]">{children}</h2>
      {extra && <span className="text-sm text-[var(--fg-2)]">{extra}</span>}
    </div>
  );
}

/**
 * "Falta lançar": contagem das pendências do período inteiro (vem pronta do banco). Com `onEscolher`, cada quadro com
 * contagem vira botão que filtra a tabela abaixo (só as linhas carregadas). Pendência que o banco ainda não manda conta 0.
 */
export function FaltaLancar({ totais, escolhida, onEscolher, idTitulo = 'mensageria-falta-lancar' }: {
  totais: Totais; escolhida?: Pendencia | null; onEscolher?: (p: Pendencia | null) => void; idTitulo?: string;
}) {
  return (
    <section aria-labelledby={idTitulo}>
      <TituloBloco id={idTitulo} extra={`no período${onEscolher ? ' · clique num quadro para filtrar a tabela' : ''}`}>
        Falta lançar
      </TituloBloco>
      <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
        {PENDENCIAS.map((p) => {
          const n = totais[p] ?? 0;
          const conteudo = (
            <>
              {/* Ponto + texto que quebra linha (o chip não cabe no quadro estreito); sem contagem, sem ponto e em cor suave. */}
              <span className={`inline-flex items-baseline gap-1.5 text-sm ${n > 0 ? (tomPendencia(p) === 'alerta' ? corAlerta : 'text-[var(--fg)]') : 'text-[var(--fg-2)]'}`}>
                {n > 0 && <span aria-hidden className="h-2 w-2 shrink-0 translate-y-[-1px] rounded-full" style={{ background: PONTO[tomPendencia(p)] }} />}
                {rotuloPendencia(p)}
              </span>
              <span className={`text-2xl font-bold leading-tight tabular ${n > 0 ? 'text-[var(--fg)]' : 'text-[var(--fg-2)]'}`}>{fmtNum(n)}</span>
            </>
          );
          const marcado = escolhida === p;
          return (
            <li key={p} className="min-w-0">
              {onEscolher && n > 0 ? (
                <button
                  type="button"
                  aria-pressed={marcado}
                  onClick={() => onEscolher(marcado ? null : p)}
                  className={`${quadroCls} min-h-11 cursor-pointer justify-between hover:border-[var(--border-strong)] ${marcado ? '!border-[var(--accent)] !bg-[var(--accent-subtle)] shadow-[inset_0_0_0_1px_var(--accent)]' : ''}`}
                >
                  {conteudo}
                </button>
              ) : <div className={`${quadroCls} justify-between`}>{conteudo}</div>}
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
        {['Canal', 'Disparos', 'Tamanho', 'Entregues', 'Lidas', 'Cliques', 'Falhas', 'Custo'].map((c, i) => <Th key={c} className={i === 0 ? thCls : thNum}>{c}</Th>)}
      </Thead>
      <tbody>
        {porCanal.map((c) => (
          <Tr key={c.canal}>
            <Td className="whitespace-nowrap">{rotuloCanal(c.canal)}</Td>
            <Td className={tdNum}><Num v={c.qtd} /></Td>
            <Td className={tdNum}><Num v={c.tamanho} /></Td>
            <Td className={tdNum}><Num v={c.entregues} /></Td>
            <Td className={tdNum}><Num v={c.lidas} /></Td>
            <Td className={tdNum}><Num v={c.cliques} /></Td>
            <Td className={tdNum}><Num v={c.falhas} /></Td>
            <Td className="text-right">
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

const COLS_DISPAROS: { l: string; num?: boolean }[] = [
  { l: 'Envio' }, { l: 'Projeto' }, { l: 'Canal' }, { l: 'Ferramenta' }, { l: 'Tipo' }, { l: 'Copy' }, { l: 'Público' },
  { l: 'Tamanho', num: true }, { l: 'Entregues', num: true }, { l: 'Lidas', num: true }, { l: 'Cliques', num: true },
  { l: 'Falhas', num: true }, { l: 'Custo', num: true }, { l: 'Quem disparou' }, { l: 'Pendências' },
];

/**
 * `onClassificar`: linha sem projeto mostra o botão "Classificar" na coluna Projeto (abre a edição). Nesse caso a
 * pendência "sem projeto" não se repete na coluna Pendências (já está dita, com a ação, duas colunas antes).
 */
export function TabelaDisparos({ linhas, acoes, onClassificar, vazio = 'Nenhum disparo neste período', dicaVazio }: {
  linhas: Disparo[]; acoes?: (d: Disparo) => React.ReactNode; onClassificar?: (d: Disparo) => void; vazio?: string; dicaVazio?: string;
}) {
  if (linhas.length === 0) return <Vazio titulo={vazio} dica={dicaVazio} />;
  return (
    <DataTable minWidth={acoes ? 1900 : 1760}>
      <Thead>
        {COLS_DISPAROS.map((c) => <Th key={c.l} className={c.num ? thNum : thCls}>{c.l}</Th>)}
        {acoes && <Th className={`${thCls} ${acoesFixasTh}`}>Ações</Th>}
      </Thead>
      <tbody>
        {linhas.map((d) => {
          const pend = onClassificar && !d.projeto ? d.pendencias.filter((p) => p !== 'sem_projeto') : d.pendencias;
          return (
            <Tr key={d.id}>
              <Td>
                <div className="whitespace-nowrap tabular">{dataHoraSP(d.enviado_em)}</div>
                {linhaDaApi(d) && <Selo title="Veio pela integração. Aqui só mudam projeto, tipo e custo.">automático · {rotuloFonte(d.origem_sistema)}</Selo>}
              </Td>
              <Td>
                {d.projeto ? <span className="font-mono font-semibold">{d.projeto}</span> : (
                  <div className="flex flex-col items-start">
                    <Selo tom="aviso">sem projeto</Selo>
                    {onClassificar && (
                      <BotaoLink onClick={() => onClassificar(d)} aria-label={`Classificar o projeto do disparo de ${dataHoraSP(d.enviado_em)}`}>
                        Classificar
                      </BotaoLink>
                    )}
                  </div>
                )}
              </Td>
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
                  <a href={d.copy_link} target="_blank" rel="noopener noreferrer" className={`block truncate underline ${corLink}`} title={d.copy_link}>
                    Abrir link
                  </a>
                )}
              </Td>
              <Td>
                <div className="whitespace-nowrap">{d.publico_lista}</div>
                {d.publico_origem && <div className="whitespace-nowrap text-[var(--fg-2)]">{d.publico_origem}</div>}
              </Td>
              <Td className={tdNum}><Num v={d.tamanho_lista} /></Td>
              <Td className={tdNum}><Num v={d.entregues} /></Td>
              <Td className={tdNum}><Num v={d.lidas} /></Td>
              <Td className={tdNum}><Num v={d.cliques} /></Td>
              <Td className={tdNum}><Num v={d.falhas} /></Td>
              <Td className="text-right"><CustoLinha d={d} /></Td>
              <Td className="whitespace-nowrap">{d.disparado_por}</Td>
              <Td>
                {pend.length === 0
                  ? <span className="text-sm text-[var(--fg-2)]">—</span>
                  : <div className="flex flex-col items-start gap-1">{pend.map((p) => <SeloPendencia key={p} p={p} />)}</div>}
              </Td>
              {acoes && <Td className={`whitespace-nowrap ${acoesFixasTd}`}>{acoes(d)}</Td>}
            </Tr>
          );
        })}
      </tbody>
    </DataTable>
  );
}
