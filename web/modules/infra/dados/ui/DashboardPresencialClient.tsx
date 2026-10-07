'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button, Tabs } from '@/shared/ui/components';
import { carregarDisparos, carregarLeads, carregarResumo, carregarSerieDiaria, carregarVendas, type Resultado } from '../infrastructure/presencial-data';
import type { DiaPresencial, DisparoPresencial, LeadPresencial, ResumoPresencial, VendaPresencial } from '../domain/presencial';
import { CardsResumo } from './CardsResumo';
import { AbaDisparos } from './AbaDisparos';
import { AbaVisaoVendas } from './AbaVisaoVendas';
import { ModalPreCheckout } from './ModalPreCheckout';
import { ModalVendas } from './ModalVendas';
import { dataBR } from './formato';
import { deveCarregar } from '../application/carga-sob-demanda';

type Estado<T> = { resultado: Resultado<T> | null; carregando: boolean };
const inicial = <T,>(): Estado<T> => ({ resultado: null, carregando: true });
// Leads e vendas só carregam quando o modal abre: começam ociosos.
const ocioso = <T,>(): Estado<T> => ({ resultado: null, carregando: false });

export function DashboardPresencialClient({ chave }: { chave: string }) {
  const [resumo, setResumo] = useState<Estado<ResumoPresencial>>(inicial);
  const [serie, setSerie] = useState<Estado<DiaPresencial[]>>(inicial);
  const [disparos, setDisparos] = useState<Estado<DisparoPresencial[]>>(inicial);
  const [leads, setLeads] = useState<Estado<LeadPresencial[]>>(ocioso);
  const [vendas, setVendas] = useState<Estado<VendaPresencial[]>>(ocioso);
  const [aba, setAba] = useState('disparos');
  const [modal, setModal] = useState<'leads' | 'vendas' | null>(null);
  const [versao, setVersao] = useState(0);

  useEffect(() => {
    let ativo = true;
    carregarResumo(chave).then((r) => { if (ativo) setResumo({ resultado: r, carregando: false }); });
    carregarSerieDiaria(chave).then((r) => { if (ativo) setSerie({ resultado: r, carregando: false }); });
    return () => { ativo = false; };
  }, [chave, versao]);

  const abrirLeads = useCallback(() => {
    setModal('leads');
    if (!deveCarregar(leads)) return;
    setLeads({ resultado: null, carregando: true });
    carregarLeads(chave).then((r) => setLeads({ resultado: r, carregando: false }));
  }, [chave, leads]);
  const abrirVendas = useCallback(() => {
    setModal('vendas');
    if (!deveCarregar(vendas)) return;
    setVendas({ resultado: null, carregando: true });
    carregarVendas(chave).then((r) => setVendas({ resultado: r, carregando: false }));
  }, [chave, vendas]);
  useEffect(() => {
    if (aba !== 'disparos' || disparos.resultado) return;
    carregarDisparos(chave).then((r) => setDisparos({ resultado: r, carregando: false }));
  }, [aba, chave, versao, disparos.resultado]);

  const atualizar = () => { setResumo(inicial()); setSerie(inicial()); setDisparos(inicial()); setLeads(ocioso()); setVendas(ocioso()); setVersao((v) => v + 1); };
  const r = resumo.resultado;
  return <div className="max-w-7xl space-y-6">
    <div className="flex flex-wrap items-start justify-between gap-3"><div><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dados / Dashboards</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">{r?.data?.projeto_nome ?? 'Dashboard presencial'}</h1>{r?.data && <p className="mt-1 text-sm text-[var(--fg-2)]">{r.data.projeto_sigla} · {dataBR(r.data.evento_inicio)} a {dataBR(r.data.evento_fim)}</p>}</div><Button onClick={atualizar} disabled={resumo.carregando || serie.carregando}>Atualizar</Button></div>
    {resumo.carregando ? <p>Carregando resumo…</p> : r?.erro ? <p role="alert">{r.erro}</p> : r?.data ? <CardsResumo resumo={r.data} abrirLeads={abrirLeads} abrirVendas={abrirVendas} /> : <p role="alert">Não foi possível carregar agora.</p>}
    <section><Tabs tabs={[{ k: 'disparos', l: 'Visão de disparos' }, { k: 'vendas', l: 'Visão geral de vendas' }]} active={aba} onChange={setAba} label="Visões do dashboard" />
      {aba === 'disparos' ? <AbaDisparos linhas={disparos.resultado?.data ?? null} erro={disparos.resultado?.erro ?? null} carregando={disparos.carregando} /> : <AbaVisaoVendas dias={serie.resultado?.data ?? null} erro={serie.resultado?.erro ?? null} carregando={serie.carregando} />}
    </section>
    {modal === 'leads' && <ModalPreCheckout linhas={leads.resultado?.data ?? null} erro={leads.resultado?.erro ?? null} carregando={leads.carregando} onClose={() => setModal(null)} />}
    {modal === 'vendas' && <ModalVendas linhas={vendas.resultado?.data ?? null} erro={vendas.resultado?.erro ?? null} carregando={vendas.carregando} onClose={() => setModal(null)} />}
  </div>;
}
