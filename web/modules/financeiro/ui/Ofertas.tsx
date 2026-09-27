'use client';

// Aba "Ofertas" do financeiro — junta o que está configurado (cobrança de saldo,
// cs.ofertas via fn_fin_ofertas) com o que de fato vendeu no espelho da Hotmart
// (fn_fin_hotmart_ofertas), por código de oferta. A junção é feita por
// `juntarOfertas` (domain/ofertas-juntar.ts) — puro, testado, sem I/O aqui.
//
// `categoria` da config é read-only (legado que mente para 3 ofertas — nunca
// editar); `papel` é o único campo editável, e só quando a linha tem
// configuração (não dá para dar um "papel" a um código que não existe no
// cadastro de ofertas). fn_fin_oferta_salvar pode não estar aplicada em
// produção ainda — a UI fica pronta e o erro de rede aparece visível no toast.
//
// HotmartOfertasVendas.tsx (extraído de ui/Hotmart.tsx, sem outro consumidor)
// foi incorporado aqui em 27/09/2026 — a visão "só vendas" virou esta aba.
import { useMemo, useState } from 'react';
import {
  Badge, Button, DataTable, EmptyState, Loading, SectionCard, Td, Th, Thead, Tr, useFlash, Toast,
} from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { Oferta } from '../domain/types';
import { juntarOfertas } from '../domain/ofertas-juntar';
import { categoriaInferida, ROTULO_CATEGORIA, ROTULO_FAMILIA, type FamiliaHotmart, type OfertaHotmart } from '../domain/hotmart';
import type { FinanceiroRepository } from '../application/ports';
import { Chip, Erro, useCarga } from './hotmart/comum';

type Filtro = 'todas' | 'cobranca' | 'sem_categoria' | 'com_venda';

export function Ofertas({ ofertas, loading, repo, canEdit, onSalvo }: {
  ofertas: Oferta[];
  loading: boolean;
  repo: FinanceiroRepository;
  canEdit: boolean;
  onSalvo: () => void;
}) {
  const { toast, flash } = useFlash();
  const [familia, setFamilia] = useState<FamiliaHotmart>('HM');
  const [filtro, setFiltro] = useState<Filtro>('todas');
  const [editando, setEditando] = useState<string | null>(null);
  const [papel, setPapel] = useState('');
  const [salvando, setSalvando] = useState(false);

  const { dados: vendas, erro: erroVendas } = useCarga<OfertaHotmart[]>(
    () => repo.loadHotmartOfertas(familia), [familia, repo]);

  const linhas = useMemo(() => juntarOfertas(ofertas, vendas ?? []), [ofertas, vendas]);

  const totais = useMemo(
    () => linhas.reduce((a, l) => ({ bruto: a.bruto + l.receitaBruta, liquido: a.liquido + l.receitaLiquida }), { bruto: 0, liquido: 0 }),
    [linhas],
  );

  const linhasFiltradas = useMemo(() => {
    switch (filtro) {
      case 'cobranca': return linhas.filter((l) => l.temConfig);
      case 'sem_categoria': return linhas.filter((l) => l.temVenda && !l.categoriaCatalogo);
      case 'com_venda': return linhas.filter((l) => l.vendasPagas > 0);
      default: return linhas;
    }
  }, [linhas, filtro]);

  const salvar = async (codigo: string) => {
    setSalvando(true);
    try {
      const r = await repo.salvarOfertaPapel(codigo, papel.trim());
      flash(r.msg || (r.ok ? 'Feito!' : 'Falhou.'));
      if (r.ok) { setEditando(null); onSalvo(); }
    } catch {
      flash('Não foi possível salvar (erro de rede).');
    } finally {
      setSalvando(false);
    }
  };

  const carregandoVendas = !vendas && !erroVendas;
  const carregandoTudo = loading || carregandoVendas;

  return (
    <SectionCard
      title="Ofertas"
      subtitle="Cada código de oferta da Hotmart, com o que está configurado para cobrança do saldo e o que de fato vendeu."
      right={
        <div className="flex flex-wrap items-center gap-2">
          {(['HM', 'AURUM', 'ACELERA'] as FamiliaHotmart[]).map((f) => (
            <button
              key={f}
              type="button"
              aria-pressed={familia === f}
              onClick={() => setFamilia(f)}
              className={`rounded-[var(--r-md)] border px-3 py-1.5 text-xs font-semibold ${familia === f ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)]'}`}
            >
              {ROTULO_FAMILIA[f]}
            </button>
          ))}
        </div>
      }
    >
      <div className="mb-3 flex flex-wrap items-center gap-1.5">
        <Chip ativo={filtro === 'todas'} onClick={() => setFiltro('todas')}>Todas</Chip>
        <Chip ativo={filtro === 'cobranca'} onClick={() => setFiltro('cobranca')} tom="info">Cobrança de saldo</Chip>
        <Chip ativo={filtro === 'sem_categoria'} onClick={() => setFiltro('sem_categoria')} tom="warning">Sem categoria no catálogo</Chip>
        <Chip ativo={filtro === 'com_venda'} onClick={() => setFiltro('com_venda')} tom="success">Com venda</Chip>
      </div>

      {erroVendas && <div className="mb-3"><Erro msg={erroVendas} /></div>}

      {carregandoTudo ? (
        <Loading label="Carregando ofertas…" minHeight={200} />
      ) : !linhasFiltradas.length ? (
        <EmptyState title={linhas.length ? 'Nenhuma oferta neste filtro' : 'Nenhuma oferta encontrada'} icon="banknote" />
      ) : (
        <DataTable minWidth={1200}>
          <Thead>
            <Th>Código</Th>
            <Th>Nome / Produto</Th>
            <Th>Categoria no catálogo</Th>
            <Th>Papel</Th>
            <Th>Valor</Th>
            <Th>Usos (board)</Th>
            <Th>Vendas pagas (Hotmart)</Th>
            <Th>Bruto</Th>
            <Th>Líquido</Th>
            <Th>Estornos</Th>
            <Th>Recusadas</Th>
            <Th>1ª / última venda</Th>
          </Thead>
          <tbody>
            {linhasFiltradas.map((l) => (
              <Tr key={l.codigo}>
                <Td>
                  <div className="flex items-center gap-1.5">
                    <span className="font-semibold text-[var(--fg)] tabular">{l.codigo}</span>
                    {l.temConfig && l.ativoConfig === false && <Badge tone="danger">Inativa</Badge>}
                  </div>
                  {l.link && (
                    <Button size="sm" variant="ghost" className="mt-1"
                      onClick={() => { navigator.clipboard?.writeText(l.link!); flash('Link copiado.'); }}>
                      <Icon name="copy" size={12} /> Copiar link
                    </Button>
                  )}
                </Td>
                <Td className="text-xs">
                  {l.nomeComercial ?? l.produto ?? <span className="text-[var(--fg-3)]">—</span>}
                  {l.produto && l.nomeComercial && l.produto !== l.nomeComercial && (
                    <div className="text-[10px] text-[var(--fg-3)]">{l.produto}</div>
                  )}
                  {l.papelProduto && <div className="text-[10px] text-[var(--fg-3)]">{l.papelProduto}</div>}
                </Td>
                <Td>
                  {!l.temVenda ? <span className="text-[var(--fg-3)]">—</span> : l.categoriaCatalogo ? (
                    <Badge tone="success">{l.categoriaCatalogo}{l.papelCatalogo ? ` · ${l.papelCatalogo}` : ''}</Badge>
                  ) : (
                    // fora do catálogo: a mesma inferência do banco (fin.oferta_categoria) — "desconhecida" quando o valor não diz
                    <Badge tone={l.vendasPagas > 0 ? 'warning' : 'neutral'}>
                      {ROTULO_CATEGORIA[categoriaInferida(l.modoPagamento, l.precoOferta)]}
                    </Badge>
                  )}
                </Td>
                <Td>
                  {editando === l.codigo ? (
                    <div className="flex items-center gap-1.5">
                      <input
                        autoFocus
                        value={papel}
                        onChange={(e) => setPapel(e.target.value)}
                        placeholder="papel da oferta"
                        className="w-32 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1 text-xs text-[var(--fg)]"
                      />
                      <Button size="sm" onClick={() => salvar(l.codigo)} disabled={salvando}>Salvar</Button>
                      <Button size="sm" variant="ghost" onClick={() => setEditando(null)}>Cancelar</Button>
                    </div>
                  ) : (
                    <div className="flex items-center gap-1.5">
                      <span className="text-[var(--fg-2)]">{l.papel ?? '—'}</span>
                      {canEdit && l.temConfig && (
                        <Button size="sm" variant="ghost" onClick={() => { setEditando(l.codigo); setPapel(l.papel ?? ''); }} title="fn_fin_oferta_salvar pode ainda não existir em produção">
                          <Icon name="pencil" size={12} />
                        </Button>
                      )}
                    </div>
                  )}
                </Td>
                <Td className="tabular text-[var(--fg)]">{l.temConfig ? fmtBRL(l.valorConfig) : '—'}</Td>
                <Td className="tabular text-[var(--fg-2)]">{l.temConfig ? l.usosBoard : '—'}</Td>
                <Td className="tabular">{l.vendasPagas}</Td>
                <Td className="tabular font-semibold">{fmtBRL(l.receitaBruta)}</Td>
                <Td className="tabular text-[var(--green)]">{fmtBRL(l.receitaLiquida)}</Td>
                <Td className="tabular">{l.estornos || '—'}</Td>
                <Td className="tabular text-[var(--fg-3)]">{l.recusadas || '—'}</Td>
                <Td className="tabular text-[11px] text-[var(--fg-3)]">
                  {l.primeiraVenda ? fmtData(l.primeiraVenda) : '—'}
                  {l.ultimaVenda && <div>{fmtData(l.ultimaVenda)}</div>}
                </Td>
              </Tr>
            ))}
          </tbody>
        </DataTable>
      )}

      {!carregandoTudo && !!linhas.length && (
        <div className="mt-3 flex flex-wrap items-center gap-4 border-t border-[var(--border-faint)] pt-3 text-xs text-[var(--fg-2)]">
          <span>Total de {ROTULO_FAMILIA[familia]} (todas as ofertas, todo o período):</span>
          <span className="font-semibold text-[var(--fg)]">Bruto {fmtBRL(totais.bruto)}</span>
          <span className="font-semibold text-[var(--green)]">Líquido {fmtBRL(totais.liquido)}</span>
        </div>
      )}

      <Toast>{toast}</Toast>
    </SectionCard>
  );
}
