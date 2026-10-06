'use client';

// Comercial: CRM (ativação, vendas, recuperação de carrinho e de venda), base única de pessoas e revisão de identidade.
// Só admin/dev por ora (gate no layout, na page e no banco: pessoas.pode_ver()). Migration 20261005o.
// /comercial?pessoa=<id> abre a ficha direto (link da Web: Marketing > Web > Visão geral > Leads na base de pessoas).
import { useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { Loading, SectionCard, Tabs, Toast, useFlash } from '@/shared/ui/components';
import type { ConfigCrm } from '../domain/crm';
import { carregarConfig, listarRevisoes, MODO_DEMO } from '../infrastructure/comercial-data';
import { CrmPainel } from './CrmPainel';
import { FichaPessoa } from './FichaPessoa';
import { PessoasPainel } from './PessoasPainel';
import { RevisaoPainel } from './RevisaoPainel';

type Aba = 'crm' | 'pessoas' | 'revisao';

export function ComercialClient() {
  const [config, setConfig] = useState<ConfigCrm | null | undefined>(undefined);
  const [aba, setAba] = useState<Aba>('crm');
  const busca = useSearchParams();
  const [ficha, setFicha] = useState<string | null>(() => {
    const p = busca.get('pessoa');
    return p && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(p) ? p : null;
  });
  const [pendentes, setPendentes] = useState<number | null>(null);
  const [versao, setVersao] = useState(0);
  const { toast, flash } = useFlash();

  useEffect(() => {
    let vivo = true;
    carregarConfig().then((c) => { if (vivo) setConfig(c); });
    return () => { vivo = false; };
  }, []);

  useEffect(() => {
    let vivo = true;
    listarRevisoes().then((r) => { if (vivo) setPendentes(r?.length ?? null); });
    return () => { vivo = false; };
  }, [versao]);

  const mudou = useCallback(() => setVersao((v) => v + 1), []);

  if (config === undefined) return <Loading />;

  return (
    <div className="max-w-7xl space-y-5">
      <div>
        <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Comercial</div>
        <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">CRM e pessoas</h1>
        <p className="mt-1 text-sm text-[var(--fg-2)]">
          Ativação, vendas e recuperação, ligados a uma base única de pessoas: o aluno que já existe é a mesma pessoa em qualquer área.
        </p>
      </div>

      {MODO_DEMO && (
        <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]">
          <b>Dados de demonstração.</b> Pessoas e negócios inventados para ver a tela (NEXT_PUBLIC_COMERCIAL_DEMO=1, só no computador local).
          Nada é gravado; recarregar a página volta ao começo.
        </p>
      )}

      {!config ? (
        <SectionCard>
          <p role="alert" className="text-sm text-[var(--red)]">
            Não foi possível carregar (erro de rede, sem acesso, ou a migration 20261005o ainda não foi aplicada).
          </p>
        </SectionCard>
      ) : (
        <>
          <Tabs
            tabs={[
              { k: 'crm', l: 'CRM' },
              { k: 'pessoas', l: 'Pessoas' },
              { k: 'revisao', l: 'Revisão de identidade', n: pendentes ?? undefined },
            ]}
            active={aba}
            onChange={(k) => setAba(k as Aba)}
            idBase="comercial"
            label="Telas do Comercial"
          />
          <div role="tabpanel" id="comercial-panel">
            {aba === 'crm' && <CrmPainel config={config} versao={versao} onAbrirPessoa={setFicha} flash={flash} onMudou={mudou} />}
            {aba === 'pessoas' && <PessoasPainel config={config} versao={versao} onAbrirPessoa={setFicha} flash={flash} onMudou={mudou} />}
            {aba === 'revisao' && <RevisaoPainel versao={versao} podeEditar={config.permissoes.pode_editar} onAbrirPessoa={setFicha} flash={flash} onMudou={mudou} />}
          </div>
        </>
      )}

      {ficha && config && (
        <FichaPessoa id={ficha} config={config} versao={versao} onFechar={() => setFicha(null)} flash={flash} onMudou={mudou} />
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
