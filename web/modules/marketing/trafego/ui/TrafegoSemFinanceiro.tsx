'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Button, DataTable, EmptyState, Loading, SectionCard, Tabs, Td, Th, Thead, Tr, Toast, useFlash } from '@/shared/ui/components';
import { listarProjetos } from '@/modules/marketing/projetos/ui/projetos-data';
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import { formDoCadastro, PROJETO_FORM_VAZIO, type ListasCadastro, type ProjetoCadastro } from '../domain/cadastro';
import type { ConfigTrafego, Conta } from '../domain/tipos';
import { carregarCadastro, carregarConfig, carregarListasCadastro, listarContas } from '../infrastructure/trafego-data';
import { ModalProjetoCadastro } from './ProjetoCadastro';
import { CampanhasPainel } from './CampanhasPainel';
import { ContasPainel } from './ContasPainel';
import { ModelosPainel } from './ModelosPainel';

type Aba = 'projetos' | 'campanhas' | 'contas' | 'modelos';

/** Vista sem financeiro.ver: não chama trafego_resumo nem trafego_projeto, que incluem receita. */
export function TrafegoSemFinanceiro({ canEdit }: { canEdit: boolean }) {
  const [projetos, setProjetos] = useState<Projeto[] | null | undefined>(undefined);
  const [novo, setNovo] = useState(false);
  const [cadastro, setCadastro] = useState<ProjetoCadastro | null>(null);
  const [aba, setAba] = useState<Aba>('projetos');
  const [carregandoForm, setCarregandoForm] = useState(false);
  const [listas, setListas] = useState<ListasCadastro | null>(null);
  const [config, setConfig] = useState<ConfigTrafego | null>(null);
  const [operacaoCarregada, setOperacaoCarregada] = useState(false);
  const [contas, setContas] = useState<Conta[]>([]);
  const [versao, setVersao] = useState(0);
  const { toast, flash } = useFlash();
  const pedirNovo = useRef(canEdit && typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('novo') === '1');

  useEffect(() => {
    let ativo = true;
    listarProjetos().then((data) => { if (ativo) setProjetos(data); });
    return () => { ativo = false; };
  }, [versao]);

  useEffect(() => {
    if (!canEdit) return;
    let ativo = true;
    Promise.all([carregarListasCadastro(), carregarConfig(), listarContas()]).then(([l, c, a]) => {
      if (!ativo) return;
      setListas(l); setConfig(c); setContas(a ?? []);
      setOperacaoCarregada(true);
    });
    return () => { ativo = false; };
  }, [canEdit]);

  const abrirNovo = useCallback(async () => {
    if (!canEdit) return;
    if (!listas || !config) {
      setCarregandoForm(true);
      const [l, c, a] = await Promise.all([carregarListasCadastro(), carregarConfig(), listarContas()]);
      setListas(l); setConfig(c); setContas(a ?? []);
      setCarregandoForm(false);
      if (!l || !c) return;
    }
    setNovo(true);
  }, [canEdit, listas, config]);

  const abrirCadastro = useCallback(async (id: number) => {
    if (!canEdit) return;
    setCarregandoForm(true);
    const [l, c, a, p] = await Promise.all([carregarListasCadastro(), carregarConfig(), listarContas(), carregarCadastro(id)]);
    setListas(l); setConfig(c); setContas(a ?? []);
    setCarregandoForm(false);
    if (!p || !l || !c) { flash('Não foi possível carregar o cadastro do projeto.'); return; }
    setCadastro(p);
  }, [canEdit, flash]);

  useEffect(() => {
    if (!pedirNovo.current || !canEdit) return;
    pedirNovo.current = false;
    void Promise.resolve().then(abrirNovo);
  }, [abrirNovo, canEdit]);

  if (projetos === undefined) return <Loading />;
  return <div className="max-w-6xl space-y-5">
    <div><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Marketing · Tráfego</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Central do Tráfego</h1><p className="mt-1 text-sm text-[var(--fg-2)]">Projetos cadastrados. Indicadores de receita exigem acesso financeiro.</p></div>
    {canEdit && <Tabs tabs={[{ k: 'projetos', l: 'Projetos' }, { k: 'campanhas', l: 'Campanhas fora do padrão' }, { k: 'contas', l: 'Contas de anúncio' }, { k: 'modelos', l: 'Modelos de lançamento' }]} active={aba} onChange={(v) => setAba(v as Aba)} label="Telas do Tráfego" />}
    {aba === 'projetos' && (projetos === null ? <p role="alert">Não foi possível carregar os projetos.</p> : <SectionCard title="Projetos" right={canEdit ? <Button disabled={carregandoForm} onClick={abrirNovo}>{carregandoForm ? 'Carregando…' : 'Novo projeto'}</Button> : undefined}>
      {projetos.length === 0 ? <EmptyState title="Nenhum projeto" /> : <DataTable><Thead><Th>Sigla</Th><Th>Nome</Th><Th>Situação</Th>{canEdit && <Th>Ação</Th>}</Thead><tbody>{projetos.map((p) => <Tr key={p.id}><Td>{p.sigla}</Td><Td>{p.nome}</Td><Td>{p.ativo ? 'Ativo' : 'Inativo'}</Td>{canEdit && <Td><Button variant="ghost" size="sm" disabled={carregandoForm} onClick={() => void abrirCadastro(p.id)}>Editar cadastro</Button></Td>}</Tr>)}</tbody></DataTable>}
    </SectionCard>)}
    {canEdit && aba === 'campanhas' && <CampanhasPainel linhas={(projetos ?? []).map((p) => ({ projeto_id: p.id, sigla: p.sigla }))} versao={versao} flash={flash} onMudou={() => setVersao((v) => v + 1)} />}
    {canEdit && aba === 'contas' && (config ? <ContasPainel config={config} flash={flash} onMudou={() => setVersao((v) => v + 1)} /> : operacaoCarregada ? <p role="alert">Não foi possível carregar a configuração de contas.</p> : <Loading />)}
    {canEdit && aba === 'modelos' && (config ? <ModelosPainel config={config} listas={listas} versao={versao} flash={flash} onMudou={() => setVersao((v) => v + 1)} /> : operacaoCarregada ? <p role="alert">Não foi possível carregar a configuração de modelos.</p> : <Loading />)}
    {canEdit && novo && listas && config && <ModalProjetoCadastro inicial={{ ...PROJETO_FORM_VAZIO }} listas={listas} config={config} contas={contas} onFechar={() => setNovo(false)} onSalvo={() => { setNovo(false); setVersao((v) => v + 1); }} />}
    {canEdit && cadastro && listas && config && <ModalProjetoCadastro inicial={formDoCadastro(cadastro)} listas={listas} config={config} contas={contas} onFechar={() => setCadastro(null)} onSalvo={() => { setCadastro(null); setVersao((v) => v + 1); }} />}
    <Toast>{toast}</Toast>
  </div>;
}
