'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
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
import { manterUltimoDado } from '../application/ultimo-dado';

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
  const [atualizando, setAtualizando] = useState(false);
  const [atualizadoEm, setAtualizadoEm] = useState<Date | null>(null);
  const atualizarLevesRef = useRef<() => boolean>(() => false);

  useEffect(() => {
    let ativo = true;
    let emAndamento = false;
    let timer: ReturnType<typeof setTimeout> | null = null;

    const agendar = () => {
      if (timer) clearTimeout(timer);
      if (ativo && document.visibilityState === 'visible') timer = setTimeout(() => { atualizar(); }, 60_000);
    };
    const atualizar = (): boolean => {
      if (!ativo || emAndamento) return false;
      emAndamento = true;
      setAtualizando(true);
      void Promise.allSettled([carregarResumo(chave), carregarSerieDiaria(chave)]).then(([resumoLido, serieLida]) => {
        if (!ativo) return;
        const erroPadrao = 'Não foi possível carregar agora.';
        const proximoResumo: Resultado<ResumoPresencial> = resumoLido.status === 'fulfilled' ? resumoLido.value : { data: null, erro: erroPadrao };
        const proximaSerie: Resultado<DiaPresencial[]> = serieLida.status === 'fulfilled' ? serieLida.value : { data: null, erro: erroPadrao };
        setResumo((anterior) => ({ resultado: manterUltimoDado(anterior.resultado, proximoResumo), carregando: false }));
        setSerie((anterior) => ({ resultado: manterUltimoDado(anterior.resultado, proximaSerie), carregando: false }));
        if (proximoResumo.data !== null && !proximoResumo.erro && proximaSerie.data !== null && !proximaSerie.erro) setAtualizadoEm(new Date());
      }).finally(() => {
        if (!ativo) return;
        emAndamento = false;
        setAtualizando(false);
        agendar();
      });
      return true;
    };
    const aoMudarVisibilidade = () => {
      if (timer) clearTimeout(timer);
      if (document.visibilityState === 'visible' && !emAndamento) atualizar();
    };

    atualizarLevesRef.current = atualizar;
    atualizar();
    document.addEventListener('visibilitychange', aoMudarVisibilidade);
    return () => {
      ativo = false;
      if (timer) clearTimeout(timer);
      document.removeEventListener('visibilitychange', aoMudarVisibilidade);
      atualizarLevesRef.current = () => false;
    };
  }, [chave]);

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

  const atualizar = () => {
    if (!atualizarLevesRef.current()) return;
    setDisparos(inicial()); setLeads(ocioso()); setVendas(ocioso()); setVersao((v) => v + 1);
  };
  const r = resumo.resultado;
  return <div className="max-w-7xl space-y-6">
    <div className="flex flex-wrap items-start justify-between gap-3"><div><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dados / Dashboards</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">{r?.data?.projeto_nome ?? 'Dashboard presencial'}</h1>{r?.data && <p className="mt-1 text-sm text-[var(--fg-2)]">{r.data.projeto_sigla} · {dataBR(r.data.evento_inicio)} a {dataBR(r.data.evento_fim)}</p>}{atualizadoEm && <p className="mt-1 text-xs text-[var(--fg-2)]" role="status">Atualizado às {atualizadoEm.toLocaleTimeString('pt-BR', { hour12: false })}</p>}</div><Button onClick={atualizar} disabled={atualizando}>Atualizar</Button></div>
    {resumo.carregando ? <p>Carregando resumo…</p> : <>{r?.erro && <p role="alert" className="text-sm text-[var(--fg-2)]">{r.erro} {r.data && 'Exibindo o último resumo carregado.'}</p>}{r?.data ? <CardsResumo resumo={r.data} abrirLeads={abrirLeads} abrirVendas={abrirVendas} /> : !r?.erro && <p role="alert">Não foi possível carregar agora.</p>}</>}
    <section><Tabs tabs={[{ k: 'disparos', l: 'Visão de disparos' }, { k: 'vendas', l: 'Visão geral de vendas' }]} active={aba} onChange={setAba} label="Visões do dashboard" />
      {aba === 'disparos' ? <AbaDisparos linhas={disparos.resultado?.data ?? null} erro={disparos.resultado?.erro ?? null} carregando={disparos.carregando} /> : <AbaVisaoVendas dias={serie.resultado?.data ?? null} erro={serie.resultado?.erro ?? null} carregando={serie.carregando} />}
    </section>
    {modal === 'leads' && <ModalPreCheckout linhas={leads.resultado?.data ?? null} erro={leads.resultado?.erro ?? null} carregando={leads.carregando} onClose={() => setModal(null)} />}
    {modal === 'vendas' && <ModalVendas linhas={vendas.resultado?.data ?? null} erro={vendas.resultado?.erro ?? null} carregando={vendas.carregando} onClose={() => setModal(null)} />}
  </div>;
}
