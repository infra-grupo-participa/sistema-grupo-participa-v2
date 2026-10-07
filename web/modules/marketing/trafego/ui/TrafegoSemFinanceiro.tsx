'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Button, DataTable, EmptyState, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { listarProjetos } from '@/modules/marketing/projetos/ui/projetos-data';
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import { PROJETO_FORM_VAZIO, type ListasCadastro } from '../domain/cadastro';
import type { ConfigTrafego, Conta } from '../domain/tipos';
import { carregarConfig, carregarListasCadastro, listarContas } from '../infrastructure/trafego-data';
import { ModalProjetoCadastro } from './ProjetoCadastro';

/** Vista sem financeiro.ver: não chama trafego_resumo nem trafego_projeto, que incluem receita. */
export function TrafegoSemFinanceiro({ canEdit }: { canEdit: boolean }) {
  const [projetos, setProjetos] = useState<Projeto[] | null | undefined>(undefined);
  const [novo, setNovo] = useState(false);
  const [carregandoForm, setCarregandoForm] = useState(false);
  const [listas, setListas] = useState<ListasCadastro | null>(null);
  const [config, setConfig] = useState<ConfigTrafego | null>(null);
  const [contas, setContas] = useState<Conta[]>([]);
  const [versao, setVersao] = useState(0);
  const pedirNovo = useRef(canEdit && typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('novo') === '1');

  useEffect(() => {
    let ativo = true;
    listarProjetos().then((data) => { if (ativo) setProjetos(data); });
    return () => { ativo = false; };
  }, [versao]);

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

  useEffect(() => {
    if (!pedirNovo.current || !canEdit) return;
    pedirNovo.current = false;
    void Promise.resolve().then(abrirNovo);
  }, [abrirNovo, canEdit]);

  if (projetos === undefined) return <Loading />;
  return <div className="max-w-6xl space-y-5">
    <div><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Marketing · Tráfego</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Central do Tráfego</h1><p className="mt-1 text-sm text-[var(--fg-2)]">Projetos cadastrados. Indicadores de receita exigem acesso financeiro.</p></div>
    {projetos === null ? <p role="alert">Não foi possível carregar os projetos.</p> : <SectionCard title="Projetos" right={canEdit ? <Button disabled={carregandoForm} onClick={abrirNovo}>{carregandoForm ? 'Carregando…' : 'Novo projeto'}</Button> : undefined}>
      {projetos.length === 0 ? <EmptyState title="Nenhum projeto" /> : <DataTable><Thead><Th>Sigla</Th><Th>Nome</Th><Th>Situação</Th></Thead><tbody>{projetos.map((p) => <Tr key={p.id}><Td>{p.sigla}</Td><Td>{p.nome}</Td><Td>{p.ativo ? 'Ativo' : 'Inativo'}</Td></Tr>)}</tbody></DataTable>}
    </SectionCard>}
    {canEdit && novo && listas && config && <ModalProjetoCadastro inicial={{ ...PROJETO_FORM_VAZIO }} listas={listas} config={config} contas={contas} onFechar={() => setNovo(false)} onSalvo={() => { setNovo(false); setVersao((v) => v + 1); }} />}
  </div>;
}
