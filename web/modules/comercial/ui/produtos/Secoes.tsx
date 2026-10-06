'use client';

// As três vistas da tela: "O que vender hoje" (cola do vendedor), "Produtos" (catálogo da Hotmart separado em
// no comercial / fora) e "Fora do catálogo" (códigos vendidos que o sistema não reconhece).
import { Badge, Button, FilterSelect, SearchInput } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtPrazo, fmtRelativo } from '@/shared/ui/format';
import type { ContaHotmart, OfertaHotmart, OfertaOrfa, ProdutoHotmart } from '../../domain/types';
import { Aviso, BotaoCopiar, NotaRodape, Segmentado, Vazio } from '../comum';
import { BotaoAbrirLink } from './CartaoOferta';
import { InfoIndicador } from '../InfoIndicador';
import { INFO_TRANSACOES_ORFA, INFO_VIGENTES } from './textos';
import {
  FILTRO_INICIAL, ROTULO_CONTA, ROTULO_ESCADA, colaDoVendedor, familias, filtrarProdutos, ordenarOrfas, resumoProduto, rotuloModo,
  type FiltroProdutos, type Lado,
} from './produtos';

// ─────────────────────────────────────────────────────────────────────────────
// O que vender hoje
// ─────────────────────────────────────────────────────────────────────────────

export function SecaoHoje({ produtos, ofertas, hojeISO, gestor, flash, onAbrir }: {
  produtos: ProdutoHotmart[]; ofertas: OfertaHotmart[]; hojeISO: string; gestor: boolean;
  flash: (m: string) => void; onAbrir: (produtoId: string) => void;
}) {
  const cola = colaDoVendedor(produtos, ofertas, hojeISO);
  if (!cola.length) {
    return <Vazio icone="receipt" titulo="Nenhum produto no comercial" hint="Vincule um produto da Hotmart ao comercial na aba Produtos." />;
  }
  return (
    <div className="space-y-3">
      <NotaRodape>O vendedor só oferece oferta vigente; condição fora dela não existe. Copie o link daqui, nunca de conversa antiga.</NotaRodape>
      <ul className="grid gap-3 md:grid-cols-2">
        {cola.map(({ produto: p, vigentes }) => (
          <li key={p.produtoId} className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3 min-w-0">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <button type="button" onClick={() => onAbrir(p.produtoId)} className="text-sm font-semibold text-[var(--fg)] text-left hover:underline focus-visible:underline truncate max-w-full">
                  {p.nomeComercial ?? p.nomeHotmart}
                </button>
                <p className="text-xs text-[var(--fg-3)] truncate">{p.escada ? ROTULO_ESCADA[p.escada] : 'Sem escada'} · {ROTULO_CONTA[p.conta]}</p>
              </div>
              <span className="text-xs text-[var(--fg-3)] shrink-0 tabular">{vigentes.length} vigente{vigentes.length === 1 ? '' : 's'}</span>
            </div>

            {vigentes.length ? (
              <ul className="mt-2 space-y-2">
                {vigentes.map((o) => {
                  const prazo = fmtPrazo(o.validaAte, hojeISO);
                  return (
                    <li key={o.codigo} className="rounded-[var(--r-md)] border border-[var(--green-border)] bg-[var(--surface-1)] px-2.5 py-2">
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <p className="text-sm font-medium text-[var(--fg)] break-words">{o.condicao ?? 'Condição não escrita'}</p>
                          <p className="mt-0.5 text-xs text-[var(--fg-3)] break-words">
                            <code className="text-[var(--fg-2)]">{o.codigo}</code> · {fmtBRL(o.preco)} · {rotuloModo(o.modo)}
                            {o.principal ? ' · principal' : ''}
                          </p>
                          {(o.uso || prazo) && (
                            <p className="mt-0.5 text-[11px] text-[var(--fg-3)] break-words">
                              {o.uso}{o.uso && prazo ? ' · ' : ''}{prazo && <span title={prazo.title}>{prazo.label}</span>}
                            </p>
                          )}
                        </div>
                        <span className="flex items-center gap-1.5 shrink-0">
                          <BotaoCopiar texto={o.linkCheckout} rotulo={`Copiar link da oferta ${o.codigo}`} onCopiado={flash} />
                          <BotaoAbrirLink href={o.linkCheckout} />
                        </span>
                      </div>
                    </li>
                  );
                })}
              </ul>
            ) : (
              <div className="mt-2 flex flex-wrap items-center justify-between gap-2 rounded-[var(--r-md)] border border-[var(--red-border)] bg-[var(--red-subtle)] px-2.5 py-2">
                <span className="inline-flex items-center gap-1.5 text-xs text-[var(--fg-2)]">
                  <Icon name="alert" size={13} className="text-[var(--red)]" />
                  Sem oferta vigente: não aborde até o gestor definir.
                </span>
                {gestor && <Button size="sm" variant="ghost" onClick={() => onAbrir(p.produtoId)}>Definir oferta</Button>}
              </div>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Produtos (catálogo da Hotmart)
// ─────────────────────────────────────────────────────────────────────────────

export function SecaoCatalogo({ produtos, ofertas, hojeISO, gestor, filtro, onFiltro, nomeAgrupador, onAbrir, onVincular, onColar }: {
  produtos: ProdutoHotmart[]; ofertas: OfertaHotmart[]; hojeISO: string; gestor: boolean;
  filtro: FiltroProdutos; onFiltro: (f: FiltroProdutos) => void; nomeAgrupador: (id: string | null) => string | null;
  onAbrir: (produtoId: string) => void; onVincular: (produtoId: string) => void; onColar: () => void;
}) {
  const lista = filtrarProdutos(produtos, ofertas, filtro, hojeISO);
  const nComercial = produtos.filter((p) => p.noComercial).length;
  const fams = familias(produtos);
  const filtrando = filtro.conta !== 'todas' || filtro.familia !== 'todas' || !!filtro.busca || filtro.semVigente;
  const limpar = () => onFiltro({ ...FILTRO_INICIAL, lado: filtro.lado });

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Segmentado<Lado>
          rotulo="Onde está o produto"
          valor={filtro.lado}
          onChange={(v) => onFiltro({ ...filtro, lado: v, semVigente: v === 'comercial' ? filtro.semVigente : false })}
          opcoes={[
            { valor: 'comercial', rotulo: 'No comercial', n: nComercial },
            { valor: 'fora', rotulo: 'Na Hotmart, fora do comercial', n: produtos.length - nComercial },
          ]}
        />
        <Segmentado<ContaHotmart | 'todas'>
          rotulo="Conta da Hotmart"
          valor={filtro.conta}
          onChange={(v) => onFiltro({ ...filtro, conta: v })}
          opcoes={[
            { valor: 'todas', rotulo: 'Todas as contas' },
            { valor: 'academy', rotulo: ROTULO_CONTA.academy },
            { valor: 'escritorio', rotulo: ROTULO_CONTA.escritorio },
          ]}
        />
        <FilterSelect aria-label="Família" value={filtro.familia} onChange={(e) => onFiltro({ ...filtro, familia: e.target.value })}>
          <option value="todas">Todas as famílias</option>
          {fams.map((f) => <option key={f} value={f}>{f}</option>)}
        </FilterSelect>
        <SearchInput
          value={filtro.busca}
          onChange={(e) => onFiltro({ ...filtro, busca: e.target.value })}
          onLimpar={() => onFiltro({ ...filtro, busca: '' })}
          placeholder="Nome, id do produto ou código de oferta"
          aria-label="Buscar produto"
        />
      </div>

      {filtro.semVigente && filtro.lado === 'comercial' && (
        <Aviso tom="neutral" icone="sliders" acao={<Button size="sm" variant="ghost" onClick={() => onFiltro({ ...filtro, semVigente: false })}>Mostrar todos</Button>}>
          Só produtos do comercial sem oferta vigente.
        </Aviso>
      )}

      {lista.length ? (
        <ul className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {lista.map((p) => (
            <CartaoProduto
              key={p.produtoId}
              produto={p}
              ofertas={ofertas}
              hojeISO={hojeISO}
              gestor={gestor}
              agrupador={nomeAgrupador(p.agrupadorId)}
              onAbrir={() => onAbrir(p.produtoId)}
              onVincular={() => onVincular(p.produtoId)}
            />
          ))}
        </ul>
      ) : filtrando ? (
        <Vazio icone="search" titulo="Nenhum produto com esses filtros" acao={<Button size="sm" variant="ghost" onClick={limpar}>Limpar filtros</Button>} />
      ) : filtro.lado === 'comercial' ? (
        <Vazio icone="link" titulo="Nenhum produto no comercial" hint="Vincule um produto que veio da Hotmart." acao={<Button size="sm" variant="ghost" onClick={() => onFiltro({ ...FILTRO_INICIAL, lado: 'fora' })}>Ver produtos fora do comercial</Button>} />
      ) : (
        <Vazio icone="check-circle" titulo="Todo produto sincronizado já está no comercial" hint="Produto novo? Crie na Hotmart; ele aparece aqui na próxima sincronização." acao={<Button size="sm" variant="ghost" onClick={onColar}>Colar link da Hotmart</Button>} />
      )}
    </div>
  );
}

function CartaoProduto({ produto: p, ofertas, hojeISO, gestor, agrupador, onAbrir, onVincular }: {
  produto: ProdutoHotmart; ofertas: OfertaHotmart[]; hojeISO: string; gestor: boolean; agrupador: string | null;
  onAbrir: () => void; onVincular: () => void;
}) {
  const r = resumoProduto(p, ofertas, hojeISO);
  const ultima = fmtRelativo(r.ultimaVendaEm);
  return (
    <li className="flex flex-col rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3 min-w-0">
      <div className="min-w-0">
        <button
          type="button"
          onClick={onAbrir}
          className="block max-w-full truncate text-left text-sm font-semibold text-[var(--fg)] hover:underline focus-visible:underline"
          aria-label={`Abrir ficha de ${p.nomeComercial ?? p.nomeHotmart}`}
        >
          {p.noComercial ? p.nomeComercial ?? p.nomeHotmart : p.nomeHotmart}
        </button>
        {p.noComercial && <p className="text-xs text-[var(--fg-3)] truncate" title={p.nomeHotmart}>Hotmart: {p.nomeHotmart}</p>}
      </div>

      <div className="mt-2 flex flex-wrap gap-1.5">
        <Badge>{ROTULO_CONTA[p.conta]}</Badge>
        {p.familia && <Badge>{p.familia}</Badge>}
        {p.noComercial && p.escada && <Badge>{ROTULO_ESCADA[p.escada]}</Badge>}
        {p.noComercial && agrupador && <Badge>{agrupador}</Badge>}
      </div>

      <dl className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-xs">
        <div><dt className="text-[var(--fg-3)]">Id Hotmart</dt><dd className="text-[var(--fg-2)] tabular">{p.produtoId}</dd></div>
        <div><dt className="text-[var(--fg-3)]">Ofertas</dt><dd className="text-[var(--fg-2)] tabular">{r.nOfertas}</dd></div>
        {p.noComercial && (
          <div>
            <dt className="inline-flex items-center gap-0.5 text-[var(--fg-3)]">Vigentes <InfoIndicador texto={INFO_VIGENTES} /></dt>
            <dd className={`tabular ${r.nVigentes ? 'text-[var(--fg)] font-semibold' : 'text-[var(--red)] font-semibold'}`}>
              {r.nVigentes}{!r.nVigentes && <span className="font-normal"> · nenhuma</span>}
              {r.nVencidas > 0 && <span className="block font-normal text-[var(--red)]">{r.nVencidas} vencida{r.nVencidas > 1 ? 's' : ''}</span>}
            </dd>
          </div>
        )}
        <div><dt className="text-[var(--fg-3)]">Última venda</dt><dd className="text-[var(--fg-2)]" title={ultima.title}>{r.ultimaVendaEm ? ultima.label : 'nunca'}</dd></div>
      </dl>

      <div className="mt-auto flex flex-wrap justify-end gap-2 pt-3">
        {!p.noComercial && gestor && (
          <Button size="sm" variant="ghost" onClick={onVincular}><Icon name="link" size={14} /> Vincular ao comercial</Button>
        )}
        <Button size="sm" variant="ghost" onClick={onAbrir}>Ver ofertas</Button>
      </div>
    </li>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Ofertas vendidas fora do catálogo
// ─────────────────────────────────────────────────────────────────────────────

export function SecaoForaDoCatalogo({ orfas, produtos, flash, onAbrir }: {
  orfas: OfertaOrfa[]; produtos: ProdutoHotmart[]; flash: (m: string) => void; onAbrir: (produtoId: string) => void;
}) {
  const lista = ordenarOrfas(orfas);
  return (
    <div className="space-y-3">
      <Aviso tom="warning" titulo="Venda que entra na Hotmart com código fora do catálogo não vira pagamento no sistema.">
        Catalogue no mesmo dia: confira se a oferta existe na conta certa da Hotmart (Academy ou Escritório) e peça a
        sincronização. Foi essa recorrência que deixou o Acelera inteiro de fora.
      </Aviso>
      {lista.length ? (
        <ul className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {lista.map((o) => {
            const p = o.produtoId ? produtos.find((x) => x.produtoId === o.produtoId) : undefined;
            const ultima = fmtRelativo(o.ultimaEm);
            return (
              <li key={o.codigo} className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3 min-w-0">
                <div className="flex items-start justify-between gap-2">
                  <code className="text-sm font-semibold text-[var(--fg)] break-all">{o.codigo}</code>
                  <BotaoCopiar texto={o.codigo} rotulo="Copiar código da oferta" onCopiado={flash} />
                </div>
                <p className="mt-1 text-xs text-[var(--fg-2)] truncate">
                  {p ? (p.nomeComercial ?? p.nomeHotmart) : o.produtoId ? `Produto ${o.produtoId} (não sincronizado)` : 'Produto desconhecido'}
                </p>
                <dl className="mt-2 grid grid-cols-2 gap-x-3 text-xs">
                  <div><dt className="inline-flex items-center gap-0.5 text-[var(--fg-3)]">Transações <InfoIndicador texto={INFO_TRANSACOES_ORFA} /></dt><dd className="font-semibold text-[var(--red)] tabular">{o.transacoes.toLocaleString('pt-BR')}</dd></div>
                  <div><dt className="text-[var(--fg-3)]">Última</dt><dd className="text-[var(--fg-2)]" title={ultima.title}>{ultima.label}</dd></div>
                </dl>
                {p && (
                  <div className="mt-2 flex justify-end">
                    <Button size="sm" variant="ghost" onClick={() => onAbrir(p.produtoId)}>Ver ofertas do produto</Button>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      ) : (
        <Vazio icone="check-circle" titulo="Nenhuma venda fora do catálogo" hint="Todo código de oferta vendido está no catálogo sincronizado." />
      )}
    </div>
  );
}
