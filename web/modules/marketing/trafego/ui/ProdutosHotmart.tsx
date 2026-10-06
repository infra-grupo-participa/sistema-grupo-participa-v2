'use client';

// Receita da Hotmart na vida do projeto: o vínculo produto Hotmart → projeto (CADASTRO À MÃO, nada pré-preenchido) e o
// que a receita está somando. Migration 20261006i: public.trafego_produtos_listar / produto_salvar / produto_apagar /
// hotmart_produtos. A receita em si é lida pelo banco de fin.hotmart_transacoes (o espelho da Hotmart do financeiro, as
// duas contas): bruto = valor da oferta das vendas pagas (APPROVED/COMPLETE), líquido à parte. Auditoria 06/10/2026: o
// vínculo leva a conta e o produto é escolhido numa lista (por conta), não digitado.
import { useEffect, useMemo, useState } from 'react';
import { Button, ConfirmDialog, DataTable, EmptyState, FilterSelect, Input, Modal, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  CONTAS_HOTMART, ROTULO_AVISO_PRODUTO, nomeContaHotmart, type LinhaResumo, type ProdutoHotmart, type ProdutoVisto, type Resposta,
} from '../domain/tipos';
import { apagarProduto, listarProdutos, listarProdutosVistos, salvarProduto, type ProdutoForm } from '../infrastructure/trafego-data';
import { SEM_DADO, dataBR, inteiro, reais } from './formato';

type Flash = (msg: string) => void;
const msg = (r: Resposta) => [r.msg, ...(r.avisos ?? []).map((a) => ROTULO_AVISO_PRODUTO[a] ?? a)].join(' ');

function Campo({ rotulo, dica, children }: { rotulo: string; dica?: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">
        {rotulo}{dica && <span className="font-normal text-[var(--fg-3)]"> · {dica}</span>}
      </span>
      {children}
    </label>
  );
}

function ModalProduto({ inicial, onFechar, onSalvo }: { inicial: ProdutoForm; onFechar: () => void; onSalvo: (m: string) => void }) {
  const [f, setF] = useState<ProdutoForm>(inicial);
  const [vistos, setVistos] = useState<ProdutoVisto[] | null | undefined>(undefined);
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = (k: keyof ProdutoForm, v: string) => setF((x) => ({ ...x, [k]: v }));

  useEffect(() => {
    let vivo = true;
    listarProdutosVistos().then((v) => { if (vivo) setVistos(v); });
    return () => { vivo = false; };
  }, []);

  // produtos da conta escolhida (o que já vendeu nela); o do vínculo em edição entra mesmo se não estiver na lista
  const daConta = useMemo(() => (vistos ?? []).filter((v) => v.conta === f.conta), [vistos, f.conta]);
  const produto = daConta.find((v) => v.produto_id === f.produto_id) ?? null;
  const foraDaLista = f.produto_id !== '' && !produto;
  const ofertas = produto?.ofertas ?? [];
  const ofertaForaDaLista = f.oferta_codigo !== '' && !ofertas.some((o) => o.codigo === f.oferta_codigo);

  async function salvar() {
    if (!f.conta) { setErro('Escolha a conta da Hotmart.'); return; }
    if (!f.produto_id.trim()) { setErro('Escolha o produto.'); return; }
    setSalvando(true);
    const r = await salvarProduto(f);
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(msg(r));
  }

  return (
    <Modal onClose={onFechar} title={f.id ? 'Editar produto da Hotmart' : 'Ligar produto da Hotmart'} width="max-w-2xl" footer={<>
      <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
      <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
    </>}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Conta da Hotmart">
          <FilterSelect className="w-full" value={f.conta} aria-label="Conta da Hotmart"
            onChange={(e) => setF((x) => ({ ...x, conta: e.target.value, produto_id: '', oferta_codigo: '' }))}>
            <option value="">Escolha a conta</option>
            {CONTAS_HOTMART.map((c) => <option key={c.codigo} value={c.codigo}>{c.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Produto" dica={vistos === undefined ? 'carregando…' : 'os que já venderam nesta conta'}>
          <FilterSelect className="w-full" value={f.produto_id} aria-label="Produto da Hotmart" disabled={!f.conta || vistos === undefined}
            onChange={(e) => setF((x) => ({ ...x, produto_id: e.target.value, oferta_codigo: '' }))}>
            <option value="">{f.conta ? 'Escolha o produto' : 'Escolha a conta primeiro'}</option>
            {foraDaLista && <option value={f.produto_id}>{f.produto_id} (sem venda nesta conta)</option>}
            {daConta.map((v) => (
              <option key={v.produto_id} value={v.produto_id}>
                {`${v.nome ?? 'sem nome'} · ${v.produto_id} · ${inteiro(v.aprovadas)} paga(s)${v.ultima ? ` · última ${dataBR(v.ultima)}` : ''}`}
              </option>
            ))}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Oferta" dica="vazio = todas as ofertas">
          <FilterSelect className="w-full" value={f.oferta_codigo} aria-label="Oferta" disabled={!f.produto_id}
            onChange={(e) => set('oferta_codigo', e.target.value)}>
            <option value="">Todas as ofertas</option>
            {ofertaForaDaLista && <option value={f.oferta_codigo}>{f.oferta_codigo} (sem venda)</option>}
            {ofertas.map((o) => (
              <option key={o.codigo} value={o.codigo}>{`${o.codigo} · ${inteiro(o.pagas)} paga(s)${o.ultima ? ` · última ${dataBR(o.ultima)}` : ''}`}</option>
            ))}
          </FilterSelect>
        </Campo>
        <div />
        <Campo rotulo="De" dica="vazio = início da captação"><Input type="date" value={f.de} onChange={(e) => set('de', e.target.value)} /></Campo>
        <Campo rotulo="Até" dica="vazio = fim do evento (ou hoje)"><Input type="date" value={f.ate} onChange={(e) => set('ate', e.target.value)} /></Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Observação"><Input value={f.obs} onChange={(e) => set('obs', e.target.value)} maxLength={1000} /></Campo>
        </div>
      </div>
      <p className="mt-2 text-xs text-[var(--fg-3)]">
        Soma o valor da oferta (bruto, sem os juros do parcelamento) das vendas pagas (APPROVED, COMPLETE) deste produto, nesta
        conta, no período, como o financeiro conta. Reembolso e chargeback saem sozinhos (a Hotmart troca o status da venda).
        Só reais entram na soma. O líquido do produtor aparece ao lado.
      </p>
      {vistos === null && <p role="alert" className="mt-2 text-sm text-[var(--red)]">Não foi possível carregar a lista de produtos da Hotmart.</p>}
      {erro && <p role="alert" className="mt-2 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}

export function ProdutosHotmart({ resumo, versao, flash, onMudou }: { resumo: LinhaResumo; versao: number; flash: Flash; onMudou: () => void }) {
  const [lista, setLista] = useState<ProdutoHotmart[] | null | undefined>(undefined);
  const [edit, setEdit] = useState<ProdutoForm | null>(null);
  const [apagar, setApagar] = useState<ProdutoHotmart | null>(null);

  useEffect(() => {
    let vivo = true;
    listarProdutos(resumo.projeto_id).then((l) => { if (vivo) setLista(l); });
    return () => { vivo = false; };
  }, [resumo.projeto_id, versao]);

  const novo = () => setEdit({ projeto_id: resumo.projeto_id, conta: '', produto_id: '', oferta_codigo: '', de: '', ate: '', obs: '' });
  const salvo = (m: string) => { setEdit(null); flash(m); onMudou(); };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <div className="text-2xl font-bold tabular">{reais(resumo.receita)}</div>
          <div className="text-xs text-[var(--fg-3)]">
            {resumo.receita_fonte === false ? 'Este banco não tem o espelho da Hotmart do financeiro (fin.hotmart_transacoes): receita sem fonte.'
              : resumo.receita == null ? (resumo.receita_vinculos ? 'Vínculo sem período (projeto sem data de início e sem "de"): ainda não soma.' : 'Sem produto ligado: sem dado.')
              : `Bruto (valor da oferta). ${inteiro(resumo.receita_compras)} venda(s) paga(s) no período${resumo.receita_outras_moedas ? `; ${resumo.receita_outras_moedas} em outra moeda, fora da soma` : ''}${resumo.receita_sem_valor ? `; ${resumo.receita_sem_valor} sem valor` : ''}.`}
          </div>
          <div className="text-xs text-[var(--fg-2)]">
            {resumo.receita != null && resumo.receita_liquida != null && <>Líquido do produtor: <span className="tabular">{reais(resumo.receita_liquida)}</span>{resumo.receita_liquido_estimado ? ` (${resumo.receita_liquido_estimado} venda(s) com o líquido estimado: oferta menos a taxa)` : ''}</>}
          </div>
        </div>
        <Button size="sm" onClick={novo}><Icon name="plus" size={14} /> Ligar produto</Button>
      </div>
      {lista === undefined ? null : lista === null ? (
        <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar (sem conexão ou sem acesso). Recarregue a página; se continuar, avise quem cuida do sistema.</p>
      ) : lista.length === 0 ? (
        <EmptyState title="Nenhum produto da Hotmart ligado a este projeto" hint="Ligue à mão o produto (e, se quiser, a oferta) que gera receita para o projeto." />
      ) : (
        <DataTable minWidth={760}>
          <Thead><Th>Conta</Th><Th>Produto</Th><Th>Oferta</Th><Th>Período que conta</Th><Th>Observação</Th><Th> </Th></Thead>
          <tbody>
            {lista.map((v) => (
              <Tr key={v.id}>
                <Td>{nomeContaHotmart(v.conta)}</Td>
                <Td>{v.produto_nome && <div>{v.produto_nome}</div>}<span className="font-mono text-xs text-[var(--fg-2)]">{v.produto_id}</span></Td>
                <Td>{v.oferta_codigo ?? <span className="text-xs text-[var(--fg-3)]">todas</span>}</Td>
                <Td>{v.de_efetivo ? `${dataBR(v.de_efetivo)} a ${v.ate_efetivo ? dataBR(v.ate_efetivo) : 'hoje'}` : <span className="text-xs text-[var(--yellow)]">sem início: não soma</span>}</Td>
                <Td>{v.obs ?? SEM_DADO}</Td>
                <Td>
                  <div className="flex gap-1">
                    <Button size="sm" variant="ghost" aria-label={`Editar ${v.produto_id}`} onClick={() => setEdit({
                      id: v.id, projeto_id: v.projeto_id, conta: v.conta, produto_id: v.produto_id, oferta_codigo: v.oferta_codigo ?? '', de: v.de ?? '', ate: v.ate ?? '', obs: v.obs ?? '',
                    })}><Icon name="pencil" size={12} /></Button>
                    <Button size="sm" variant="danger" aria-label={`Apagar ${v.produto_id}`} onClick={() => setApagar(v)}><Icon name="trash" size={12} /></Button>
                  </div>
                </Td>
              </Tr>
            ))}
          </tbody>
        </DataTable>
      )}
      {edit && <ModalProduto inicial={edit} onFechar={() => setEdit(null)} onSalvo={salvo} />}
      {apagar && (
        <ConfirmDialog
          title="Apagar vínculo"
          message={`Tirar o produto ${apagar.produto_nome ?? apagar.produto_id} (${nomeContaHotmart(apagar.conta)})${apagar.oferta_codigo ? ` (oferta ${apagar.oferta_codigo})` : ''} da receita de ${resumo.sigla}? As compras continuam na Hotmart; só deixam de contar aqui.`}
          confirmLabel="Apagar"
          danger
          onCancel={() => setApagar(null)}
          onConfirm={async () => { const id = apagar.id; setApagar(null); const r = await apagarProduto(id); flash(r.msg); if (r.ok) onMudou(); }}
        />
      )}
    </div>
  );
}
