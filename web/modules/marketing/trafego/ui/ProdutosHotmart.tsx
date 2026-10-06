'use client';

// Receita da Hotmart na vida do projeto: o vínculo produto Hotmart → projeto (CADASTRO À MÃO, nada pré-preenchido) e o
// que a receita está somando. Migration 20261006i: public.trafego_produtos_listar / produto_salvar / produto_apagar /
// hotmart_produtos. A receita em si é lida pelo banco de fin.hotmart_transacoes (o espelho da Hotmart do financeiro, as
// duas contas): bruto = valor da oferta das vendas pagas (APPROVED/COMPLETE), líquido à parte. Auditoria 06/10/2026: o
// vínculo leva a conta e o produto é escolhido numa lista (por conta), não digitado.
// Decisão do Victor, 06/10/2026 (docs/central-de-dados.md, "Receita do projeto: oferta exclusiva e SCK"): a receita tem
// NÍVEL DE CERTEZA. 1 oferta exclusiva, 2 SCK com o projeto, 3 comprador que foi lead do projeto = a receita do projeto;
// 4 só produto + período = estimada, à parte. Venda que casa com dois projetos no mesmo nível = disputa (não soma). A
// quebra e as disputas vêm de public.trafego_receita; o vínculo ganha a marca "oferta exclusiva deste projeto".
import { useEffect, useMemo, useState } from 'react';
import { Badge, Button, ConfirmDialog, DataTable, EmptyState, FilterSelect, Input, Modal, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  ROTULO_AVISO_PRODUTO, contaHotmartDaUnidade, motivoSemConta, ROTULO_NIVEL, nomeContaHotmart, type LinhaResumo, type ProdutoHotmart, type ProdutoVisto,
  type ReceitaProjeto, type Resposta,
} from '../domain/tipos';
import {
  apagarProduto, carregarReceita, listarProdutos, listarProdutosVistos, salvarProduto, type ProdutoForm,
} from '../infrastructure/trafego-data';
import { SEM_DADO, dataBR, inteiro, quebraReceita, reais } from './formato';

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
    listarProdutosVistos(inicial.projeto_id).then((v) => { if (vivo) setVistos(v); });
    return () => { vivo = false; };
  }, [inicial.projeto_id]);

  // produtos da conta da unidade do projeto (o banco já manda só eles); o do vínculo em edição entra mesmo se não estiver na lista
  const daConta = useMemo(() => (vistos ?? []).filter((v) => v.conta === f.conta), [vistos, f.conta]);
  const produto = daConta.find((v) => v.produto_id === f.produto_id) ?? null;
  const foraDaLista = f.produto_id !== '' && !produto;
  const ofertas = produto?.ofertas ?? [];
  const ofertaForaDaLista = f.oferta_codigo !== '' && !ofertas.some((o) => o.codigo === f.oferta_codigo);
  const donoDaOferta = ofertas.find((o) => o.codigo === f.oferta_codigo)?.exclusiva_de ?? null;

  async function salvar() {
    if (!f.produto_id.trim()) { setErro('Escolha o produto.'); return; }
    if (f.oferta_exclusiva && !f.oferta_codigo) { setErro('Oferta exclusiva precisa da oferta: escolha a oferta criada na Hotmart só para este projeto.'); return; }
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
        <Campo rotulo="Conta da Hotmart" dica="vem da unidade do projeto">
          <div className="py-1.5 text-sm" title="CSM lê só a conta academy; Escritório só a escritorio (decisão do Victor, 06/10/2026). Para trocar, mude a unidade no cadastro do projeto.">{nomeContaHotmart(f.conta)}</div>
        </Campo>
        <Campo rotulo="Produto" dica={vistos === undefined ? 'carregando…' : 'os que já venderam nesta conta'}>
          <FilterSelect className="w-full" value={f.produto_id} aria-label="Produto da Hotmart" disabled={vistos === undefined}
            onChange={(e) => setF((x) => ({ ...x, produto_id: e.target.value, oferta_codigo: '' }))}>
            <option value="">Escolha o produto</option>
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
            onChange={(e) => setF((x) => ({ ...x, oferta_codigo: e.target.value, oferta_exclusiva: e.target.value ? x.oferta_exclusiva : false }))}>
            <option value="">Todas as ofertas</option>
            {ofertaForaDaLista && <option value={f.oferta_codigo}>{f.oferta_codigo} (sem venda)</option>}
            {ofertas.map((o) => (
              <option key={o.codigo} value={o.codigo}>{`${o.codigo} · ${inteiro(o.pagas)} paga(s)${o.ultima ? ` · última ${dataBR(o.ultima)}` : ''}${o.exclusiva_de ? ` · exclusiva de ${o.exclusiva_de}` : ''}`}</option>
            ))}
          </FilterSelect>
        </Campo>
        <div className="flex items-end">
          <label className="flex items-start gap-2 text-sm" title="Marque só se a oferta foi criada na Hotmart para este projeto e não é vendida por mais ninguém (comercial, recuperação, outro lançamento).">
            <input type="checkbox" className="mt-1" checked={f.oferta_exclusiva} disabled={!f.oferta_codigo}
              onChange={(e) => setF((x) => ({ ...x, oferta_exclusiva: e.target.checked }))} />
            <span>Oferta exclusiva deste projeto
              <span className="block text-xs text-[var(--fg-3)]">{f.oferta_codigo ? 'toda venda dela conta como receita certa do projeto' : 'escolha a oferta primeiro'}</span>
            </span>
          </label>
        </div>
        {f.oferta_exclusiva && donoDaOferta && (
          <p role="alert" className="sm:col-span-2 text-sm text-[var(--red)]">Esta oferta já é exclusiva de {donoDaOferta}. Uma oferta só pode ser exclusiva de um projeto: crie outra oferta na Hotmart.</p>
        )}
        <Campo rotulo="De" dica="vazio = início da captação"><Input type="date" value={f.de} onChange={(e) => set('de', e.target.value)} /></Campo>
        <Campo rotulo="Até" dica="vazio = fim do evento (ou hoje)"><Input type="date" value={f.ate} onChange={(e) => set('ate', e.target.value)} /></Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Observação"><Input value={f.obs} onChange={(e) => set('obs', e.target.value)} maxLength={1000} /></Campo>
        </div>
      </div>
      <p className="mt-2 text-xs text-[var(--fg-3)]">
        Valor da oferta (bruto, sem os juros do parcelamento) das vendas pagas (APPROVED, COMPLETE), como o financeiro conta.
        Reembolso e chargeback saem sozinhos (a Hotmart troca o status da venda). Só reais entram na soma.
      </p>
      <p className="mt-1 text-xs text-[var(--fg-3)]">
        <strong>Oferta exclusiva</strong>: toda venda dela é receita certa do projeto, em qualquer data (só o De/Até deste vínculo, se
        preenchido, limita). <strong>Sem a marca</strong>: as vendas do produto no período ficam como <strong>estimada</strong>, à parte,
        e só sobem para a receita do projeto se o checkout trouxer o SCK do projeto ou se o comprador tiver sido lead do projeto antes.
      </p>
      {vistos === null && <p role="alert" className="mt-2 text-sm text-[var(--red)]">Não foi possível carregar a lista de produtos da Hotmart.</p>}
      {erro && <p role="alert" className="mt-2 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}

/**
 * A receita do projeto por nível de certeza (vida do projeto): o número que conta (níveis 1 a 3), a quebra, a estimada à
 * parte, o aviso grande sem oferta exclusiva e as vendas em disputa. Só apresenta (o banco faz a conta).
 */
export function ReceitaNiveis({ resumo, rec }: { resumo: LinhaResumo; rec: ReceitaProjeto | null | undefined }) {
  const r = { ...resumo, ...(rec?.receita ?? {}) };
  const quebra = quebraReceita(r);
  return (
    <div className="space-y-3">
      {rec?.sem_oferta_exclusiva && (
        <div role="alert" className="rounded-lg border-2 border-[var(--yellow-border-forte)] bg-[var(--yellow-subtle)] p-3">
          <div className="text-base font-bold text-[var(--yellow)]">Sem oferta exclusiva, a receita é só estimada</div>
          <p className="mt-1 text-sm text-[var(--fg-2)]">
            Este projeto tem produto ligado mas nenhuma oferta exclusiva. Produto + período não garante que a venda veio do projeto (o
            mesmo produto é vendido pelo comercial, pela recuperação e por outros lançamentos). O que fazer: criar na Hotmart uma oferta
            só para esta ação, usar essa oferta no checkout e ligar aqui com &quot;Oferta exclusiva deste projeto&quot; marcada.
          </p>
        </div>
      )}
      <div>
        <div className="text-2xl font-bold tabular">{reais(r.receita)}</div>
        <div className="text-xs text-[var(--fg-3)]">
          {r.receita_fonte === false ? 'Este banco não tem o espelho da Hotmart do financeiro (fin.hotmart_transacoes): receita sem fonte.'
            : r.receita == null ? (r.receita_vinculos ? 'Vínculo sem período (projeto sem data de início e sem "de"): ainda não soma.' : 'Sem produto ligado e sem venda com o SCK do projeto: sem dado.')
            : `Receita do projeto (níveis 1 a 3), bruto. ${inteiro(r.receita_compras)} venda(s)${r.receita_outras_moedas ? `; ${r.receita_outras_moedas} em outra moeda, fora da soma` : ''}${r.receita_sem_valor ? `; ${r.receita_sem_valor} sem valor` : ''}.`}
        </div>
        {r.receita != null && r.receita_liquida != null && (
          <div className="text-xs text-[var(--fg-2)]">Líquido do produtor: <span className="tabular">{reais(r.receita_liquida)}</span>{r.receita_liquido_estimado ? ` (${r.receita_liquido_estimado} venda(s) com o líquido estimado: oferta menos a taxa)` : ''}</div>
        )}
      </div>
      {r.receita_fonte !== false && (
        <DataTable minWidth={520}>
          <Thead><Th>Nível</Th><Th>Valor</Th><Th>Vendas</Th></Thead>
          <tbody>
            {quebra.map((q, i) => (
              <Tr key={q.rotulo}>
                <Td><span title={ROTULO_NIVEL[(i + 1) as 1 | 2 | 3 | 4].regra} className={i === 3 ? 'text-[var(--fg-3)]' : ''}>{q.rotulo}</span></Td>
                <Td><span className={`tabular ${i === 3 ? 'text-[var(--fg-3)]' : ''}`}>{reais(q.valor)}</span></Td>
                <Td><span className="tabular">{q.vendas == null ? SEM_DADO : inteiro(q.vendas)}</span></Td>
              </Tr>
            ))}
          </tbody>
        </DataTable>
      )}
      {rec && !rec.base_pessoas && <p className="text-xs text-[var(--fg-3)]">Nível 3 fora: a base de pessoas não está neste banco.</p>}
      {rec && rec.disputas_total > 0 && (
        <div>
          <div className="text-sm font-semibold">Vendas em disputa ({inteiro(rec.disputas_total)})</div>
          <p className="text-xs text-[var(--fg-3)]">Casam com mais de um projeto no mesmo nível: não somam em nenhum. Resolva com oferta exclusiva ou SCK do projeto.</p>
          <DataTable minWidth={640}>
            <Thead><Th>Dia</Th><Th>Transação</Th><Th>Produto / oferta</Th><Th>Nível</Th><Th>Valor</Th><Th>Projetos</Th></Thead>
            <tbody>
              {rec.disputas.map((d) => (
                <Tr key={d.transacao}>
                  <Td>{dataBR(d.dia)}</Td>
                  <Td><span className="font-mono text-xs">{d.transacao}</span></Td>
                  <Td><span className="font-mono text-xs">{d.produto_id}{d.oferta_codigo ? ` / ${d.oferta_codigo}` : ''}</span><div className="text-[11px] text-[var(--fg-3)]">{nomeContaHotmart(d.conta)}</div></Td>
                  <Td>{ROTULO_NIVEL[d.nivel]?.nome ?? d.nivel}</Td>
                  <Td><span className="tabular">{d.moeda === 'BRL' ? reais(d.valor) : `${d.valor ?? SEM_DADO} ${d.moeda}`}</span></Td>
                  <Td>{d.projetos.join(', ')}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
          {rec.disputas_total > rec.disputas.length && <p className="text-xs text-[var(--fg-3)]">Mostrando as {rec.disputas.length} mais recentes.</p>}
        </div>
      )}
      <details className="text-xs text-[var(--fg-2)]">
        <summary className="cursor-pointer">Como a receita do projeto é contada</summary>
        <ul className="mt-1 list-disc space-y-1 pl-5">
          {([1, 2, 3, 4] as const).map((n) => (
            <li key={n}><strong>{n}. {ROTULO_NIVEL[n].nome}</strong> ({ROTULO_NIVEL[n].certeza}): {ROTULO_NIVEL[n].regra}</li>
          ))}
          <li>Cada venda conta uma vez, no nível mais forte. Receita do projeto e ROAS usam só os níveis 1 a 3.</li>
          <li>SCK no formato {rec?.sck_formato ?? 'origem|meio|campanha|conteúdo|termo'}; no campo campanha vale {rec?.sck_chaves?.length ? rec.sck_chaves.join(' ou ') : 'a chave do projeto ou a sigla'} (sem diferença de maiúscula e acento). Tráfego pago fica de fora do SCK: ali valem a UTM e a oferta exclusiva.</li>
        </ul>
      </details>
    </div>
  );
}

export function ProdutosHotmart({ resumo, versao, flash, onMudou }: { resumo: LinhaResumo; versao: number; flash: Flash; onMudou: () => void }) {
  const [lista, setLista] = useState<ProdutoHotmart[] | null | undefined>(undefined);
  const [rec, setRec] = useState<ReceitaProjeto | null | undefined>(undefined);
  const [edit, setEdit] = useState<ProdutoForm | null>(null);
  const [apagar, setApagar] = useState<ProdutoHotmart | null>(null);

  useEffect(() => {
    let vivo = true;
    listarProdutos(resumo.projeto_id).then((l) => { if (vivo) setLista(l); });
    carregarReceita(resumo.projeto_id).then((r) => { if (vivo) setRec(r); });
    return () => { vivo = false; };
  }, [resumo.projeto_id, versao]);

  // conta da Hotmart = unidade do projeto (decisão do Victor, 06/10/2026); sem conta, não liga produto e mostra o motivo
  const conta = resumo.receita_conta ?? contaHotmartDaUnidade(resumo.unidade);
  const motivo = conta ? null : motivoSemConta(resumo) ?? 'Projeto sem conta da Hotmart.';
  const novo = () => conta && setEdit({ projeto_id: resumo.projeto_id, conta, produto_id: '', oferta_codigo: '', oferta_exclusiva: false, de: '', ate: '', obs: '' });
  const salvo = (m: string) => { setEdit(null); flash(m); onMudou(); };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0 flex-1"><ReceitaNiveis resumo={resumo} rec={rec} /></div>
        <Button size="sm" onClick={novo} disabled={!conta} title={motivo ?? `Conta da Hotmart deste projeto: ${nomeContaHotmart(conta ?? '')}`}><Icon name="plus" size={14} /> Ligar produto</Button>
      </div>
      {motivo
        ? <p role="note" className="text-sm text-[var(--yellow)]">{motivo}</p>
        : <p className="text-xs text-[var(--fg-3)]">Conta da Hotmart deste projeto: <strong>{nomeContaHotmart(conta ?? '')}</strong> (vem da unidade: CSM = academy, Escritório = escritorio).</p>}
      {!!resumo.receita_vinculos_fora_conta && <p className="text-xs text-[var(--yellow)]">{inteiro(resumo.receita_vinculos_fora_conta)} vínculo(s) de outra conta (a unidade mudou depois): não somam. Apague e ligue de novo.</p>}
      {lista === undefined ? null : lista === null ? (
        <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar (sem conexão ou sem acesso). Recarregue a página; se continuar, avise quem cuida do sistema.</p>
      ) : lista.length === 0 ? (
        <EmptyState title="Nenhum produto da Hotmart ligado a este projeto" hint="Ligue a oferta exclusiva do projeto (receita certa) e, se quiser, o produto inteiro (receita estimada, à parte)." />
      ) : (
        <DataTable minWidth={760}>
          <Thead><Th>Conta</Th><Th>Produto</Th><Th>Oferta</Th><Th>Período que conta</Th><Th>Observação</Th><Th> </Th></Thead>
          <tbody>
            {lista.map((v) => (
              <Tr key={v.id}>
                <Td>{nomeContaHotmart(v.conta)}{v.conta_ok === false && <div className="text-[11px] text-[var(--yellow)]">não é a conta da unidade: não soma</div>}</Td>
                <Td>{v.produto_nome && <div>{v.produto_nome}</div>}<span className="font-mono text-xs text-[var(--fg-2)]">{v.produto_id}</span></Td>
                <Td>{v.oferta_codigo ?? <span className="text-xs text-[var(--fg-3)]">todas</span>}
                  {v.oferta_exclusiva
                    ? <div><Badge tone="success">oferta exclusiva deste projeto</Badge></div>
                    : <div className="text-[11px] text-[var(--fg-3)]" title="Vendas deste vínculo contam como estimada (à parte), a não ser que tenham SCK do projeto ou o comprador tenha sido lead do projeto">estimada</div>}</Td>
                <Td>{v.oferta_exclusiva
                  ? (v.de || v.ate ? `${v.de ? dataBR(v.de) : 'qualquer data'} a ${v.ate ? dataBR(v.ate) : 'hoje'}` : 'qualquer data')
                  : v.de_efetivo ? `${dataBR(v.de_efetivo)} a ${v.ate_efetivo ? dataBR(v.ate_efetivo) : 'hoje'}` : <span className="text-xs text-[var(--yellow)]">sem início: não soma</span>}</Td>
                <Td>{v.obs ?? SEM_DADO}</Td>
                <Td>
                  <div className="flex gap-1">
                    <Button size="sm" variant="ghost" aria-label={`Editar ${v.produto_id}`} onClick={() => setEdit({
                      id: v.id, projeto_id: v.projeto_id, conta: v.conta, produto_id: v.produto_id, oferta_codigo: v.oferta_codigo ?? '', oferta_exclusiva: !!v.oferta_exclusiva,
                      de: v.de ?? '', ate: v.ate ?? '', obs: v.obs ?? '',
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
