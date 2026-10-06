'use client';

// Receita da Hotmart na vida do projeto: o vínculo produto Hotmart → projeto (CADASTRO À MÃO, nada pré-preenchido) e o
// que a receita está somando. Migration 20261006i: public.trafego_produtos_listar / produto_salvar / produto_apagar /
// hotmart_produtos. A receita em si é lida de public.compras pelo banco (a Hotmart manda no dinheiro).
import { useEffect, useState } from 'react';
import { Button, ConfirmDialog, DataTable, EmptyState, Input, Modal, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_AVISO_PRODUTO, type LinhaResumo, type ProdutoHotmart, type ProdutoVisto, type Resposta } from '../domain/tipos';
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
  const [vistos, setVistos] = useState<ProdutoVisto[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = (k: keyof ProdutoForm, v: string) => setF((x) => ({ ...x, [k]: v }));

  useEffect(() => {
    let vivo = true;
    listarProdutosVistos().then((v) => { if (vivo) setVistos(v ?? []); });
    return () => { vivo = false; };
  }, []);

  async function salvar() {
    if (!f.produto_id.trim()) { setErro('Informe o id do produto na Hotmart.'); return; }
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
        <Campo rotulo="Id do produto na Hotmart" dica="como em public.compras">
          <Input value={f.produto_id} onChange={(e) => set('produto_id', e.target.value.trim())} list="produtos-hotmart-vistos" maxLength={40} />
          <datalist id="produtos-hotmart-vistos">
            {(vistos ?? []).map((v) => <option key={v.produto_id} value={v.produto_id}>{`${v.nome ?? 'sem nome'} · ${v.aprovadas} aprovadas · última ${dataBR(v.ultima)}`}</option>)}
          </datalist>
        </Campo>
        <Campo rotulo="Código da oferta" dica="vazio = todas as ofertas">
          <Input value={f.oferta_codigo} onChange={(e) => set('oferta_codigo', e.target.value.trim())} maxLength={40} />
        </Campo>
        <Campo rotulo="De" dica="vazio = início da captação"><Input type="date" value={f.de} onChange={(e) => set('de', e.target.value)} /></Campo>
        <Campo rotulo="Até" dica="vazio = fim do evento (ou hoje)"><Input type="date" value={f.ate} onChange={(e) => set('ate', e.target.value)} /></Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Observação"><Input value={f.obs} onChange={(e) => set('obs', e.target.value)} maxLength={1000} /></Campo>
        </div>
      </div>
      <p className="mt-2 text-xs text-[var(--fg-3)]">
        Soma o valor das compras aprovadas (APPROVED, COMPLETE, COMPLETED) deste produto no período. Reembolso e chargeback saem
        sozinhos (a Hotmart troca o status da compra). Só reais entram na soma.
        {vistos && vistos.length > 0 && ' O campo do id sugere os produtos que já venderam.'}
      </p>
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

  const novo = () => setEdit({ projeto_id: resumo.projeto_id, produto_id: '', oferta_codigo: '', de: '', ate: '', obs: '' });
  const salvo = (m: string) => { setEdit(null); flash(m); onMudou(); };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <div className="text-2xl font-bold tabular">{reais(resumo.receita)}</div>
          <div className="text-xs text-[var(--fg-3)]">
            {resumo.receita_fonte === false ? 'Este banco não tem as colunas da Hotmart em public.compras: receita sem fonte.'
              : resumo.receita == null ? (resumo.receita_vinculos ? 'Vínculo sem período (projeto sem data de início e sem "de"): ainda não soma.' : 'Sem produto ligado: sem dado.')
              : `${inteiro(resumo.receita_compras)} compra(s) aprovada(s) no período${resumo.receita_outras_moedas ? `; ${resumo.receita_outras_moedas} em outra moeda, fora da soma` : ''}${resumo.receita_sem_valor ? `; ${resumo.receita_sem_valor} sem valor` : ''}.`}
          </div>
        </div>
        <Button size="sm" onClick={novo}><Icon name="plus" size={14} /> Ligar produto</Button>
      </div>
      {lista === undefined ? null : lista === null ? (
        <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar (sem conexão ou sem acesso). Recarregue a página; se continuar, avise quem cuida do sistema.</p>
      ) : lista.length === 0 ? (
        <EmptyState title="Nenhum produto da Hotmart ligado a este projeto" hint="Ligue à mão o produto (e, se quiser, a oferta) que gera receita para o projeto." />
      ) : (
        <DataTable minWidth={640}>
          <Thead><Th>Produto</Th><Th>Oferta</Th><Th>Período que conta</Th><Th>Observação</Th><Th> </Th></Thead>
          <tbody>
            {lista.map((v) => (
              <Tr key={v.id}>
                <Td><span className="font-mono">{v.produto_id}</span></Td>
                <Td>{v.oferta_codigo ?? <span className="text-xs text-[var(--fg-3)]">todas</span>}</Td>
                <Td>{v.de_efetivo ? `${dataBR(v.de_efetivo)} a ${v.ate_efetivo ? dataBR(v.ate_efetivo) : 'hoje'}` : <span className="text-xs text-[var(--yellow)]">sem início: não soma</span>}</Td>
                <Td>{v.obs ?? SEM_DADO}</Td>
                <Td>
                  <div className="flex gap-1">
                    <Button size="sm" variant="ghost" aria-label={`Editar ${v.produto_id}`} onClick={() => setEdit({
                      id: v.id, projeto_id: v.projeto_id, produto_id: v.produto_id, oferta_codigo: v.oferta_codigo ?? '', de: v.de ?? '', ate: v.ate ?? '', obs: v.obs ?? '',
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
          message={`Tirar o produto ${apagar.produto_id}${apagar.oferta_codigo ? ` (oferta ${apagar.oferta_codigo})` : ''} da receita de ${resumo.sigla}? As compras continuam na Hotmart; só deixam de contar aqui.`}
          confirmLabel="Apagar"
          danger
          onCancel={() => setApagar(null)}
          onConfirm={async () => { const id = apagar.id; setApagar(null); const r = await apagarProduto(id); flash(r.msg); if (r.ok) onMudou(); }}
        />
      )}
    </div>
  );
}
