'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Button, Tabs } from '@/shared/ui/components';
import { carregarDisparos, carregarLeads, carregarPagamentos, carregarPendencias, carregarPerfilCompradores, carregarPessoasPendencias, carregarResumo, carregarSerieDiaria, carregarSerieVendas, carregarVendas, carregarVendasPorHora, type Resultado } from '../infrastructure/presencial-data';
import type { DiaPresencial, DisparoPresencial, GrupoPendencia, LeadPresencial, PagamentoPresencial, PendenciaPresencial, PerfilCompradorPresencial, PessoaPendenciaPresencial, ResumoPresencial, SerieVendasPresencial, VendaHoraPresencial, VendaPresencial } from '../domain/presencial';
import { CardsResumo } from './CardsResumo';
import { AbaDisparos } from './AbaDisparos';
import { AbaVisaoVendas } from './AbaVisaoVendas';
import { ModalPreCheckout } from './ModalPreCheckout';
import { ModalVendas } from './ModalVendas';
import { ModalPendencias } from './ModalPendencias';
import { dataBR } from './formato';
import { deveCarregar } from '../application/carga-sob-demanda';
import { manterUltimoDado, type EstadoLeitura } from '../application/ultimo-dado';

const inicial = <T,>(): EstadoLeitura<T> => ({ resultado: null, carregando: true });
// Leads e vendas só carregam quando o modal abre: começam ociosos.
const ocioso = <T,>(): EstadoLeitura<T> => ({ resultado: null, carregando: false });
const falha = <T,>(lido: PromiseSettledResult<Resultado<T>>): Resultado<T> => lido.status === 'fulfilled' ? lido.value : { data: null, erro: 'Não foi possível carregar agora.' };

export function DashboardPresencialClient({ chave }: { chave: string }) {
  const [resumo, setResumo] = useState<EstadoLeitura<ResumoPresencial>>(inicial);
  const [serie, setSerie] = useState<EstadoLeitura<DiaPresencial[]>>(inicial);
  const [pagamentos, setPagamentos] = useState<EstadoLeitura<PagamentoPresencial[]>>(inicial);
  const [perfil, setPerfil] = useState<EstadoLeitura<PerfilCompradorPresencial[]>>(inicial);
  const [pendencias, setPendencias] = useState<EstadoLeitura<PendenciaPresencial[]>>(inicial);
  const [serieVendas, setSerieVendas] = useState<EstadoLeitura<SerieVendasPresencial[]>>(inicial);
  const [porHora, setPorHora] = useState<EstadoLeitura<VendaHoraPresencial[]>>(inicial);
  const [disparos, setDisparos] = useState<EstadoLeitura<DisparoPresencial[]>>(inicial);
  const [leads, setLeads] = useState<EstadoLeitura<LeadPresencial[]>>(ocioso);
  const [vendas, setVendas] = useState<EstadoLeitura<VendaPresencial[]>>(ocioso);
  const [pessoasPendencias, setPessoasPendencias] = useState<Record<GrupoPendencia, EstadoLeitura<PessoaPendenciaPresencial[]>>>({ nao_pago: ocioso(), cancelada: ocioso() });
  const [aba, setAba] = useState('disparos');
  const [modal, setModal] = useState<'leads' | 'vendas' | null>(null);
  const [modalPendencias, setModalPendencias] = useState<GrupoPendencia | null>(null);
  const [versao, setVersao] = useState(0);
  const [atualizando, setAtualizando] = useState(false);
  const [atualizadoEm, setAtualizadoEm] = useState<Date | null>(null);
  const atualizarLevesRef = useRef<() => boolean>(() => false);
  const pendenciasEmAndamento = useRef<Record<GrupoPendencia, boolean>>({ nao_pago: false, cancelada: false });

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
      void Promise.allSettled([carregarResumo(chave), carregarSerieDiaria(chave), carregarPagamentos(chave), carregarPerfilCompradores(chave), carregarPendencias(chave), carregarSerieVendas(chave), carregarVendasPorHora(chave)]).then(([resumoLido, serieLida, pagamentosLidos, perfilLido, pendenciasLidas, serieVendasLida, porHoraLido]) => {
        if (!ativo) return;
        const proximoResumo = falha(resumoLido);
        const proximaSerie = falha(serieLida);
        setResumo((anterior) => ({ resultado: manterUltimoDado(anterior.resultado, proximoResumo), carregando: false }));
        setSerie((anterior) => ({ resultado: manterUltimoDado(anterior.resultado, proximaSerie), carregando: false }));
        setPagamentos((anterior) => ({ resultado: manterUltimoDado(anterior.resultado, falha(pagamentosLidos)), carregando: false }));
        setPerfil((anterior) => ({ resultado: manterUltimoDado(anterior.resultado, falha(perfilLido)), carregando: false }));
        setPendencias((anterior) => ({ resultado: manterUltimoDado(anterior.resultado, falha(pendenciasLidas)), carregando: false }));
        setSerieVendas((anterior) => ({ resultado: manterUltimoDado(anterior.resultado, falha(serieVendasLida)), carregando: false }));
        setPorHora((anterior) => ({ resultado: manterUltimoDado(anterior.resultado, falha(porHoraLido)), carregando: false }));
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
  const abrirPendencias = useCallback((grupo: GrupoPendencia) => {
    setModalPendencias(grupo);
    if (pendenciasEmAndamento.current[grupo]) return;
    pendenciasEmAndamento.current[grupo] = true;
    setPessoasPendencias((anterior) => ({ ...anterior, [grupo]: { ...anterior[grupo], carregando: anterior[grupo].resultado?.data === null || anterior[grupo].resultado === null } }));
    void carregarPessoasPendencias(chave, grupo).then((lido) => {
      setPessoasPendencias((anterior) => ({ ...anterior, [grupo]: { resultado: manterUltimoDado(anterior[grupo].resultado, lido), carregando: false } }));
    }).finally(() => { pendenciasEmAndamento.current[grupo] = false; });
  }, [chave]);
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
      {aba === 'disparos' ? <AbaDisparos linhas={disparos.resultado?.data ?? null} erro={disparos.resultado?.erro ?? null} carregando={disparos.carregando} /> : <AbaVisaoVendas dias={serie} pagamentos={pagamentos} perfil={perfil} pendencias={pendencias} serieVendas={serieVendas} porHora={porHora} abrirPendencias={abrirPendencias} />}
    </section>
    {modal === 'leads' && <ModalPreCheckout linhas={leads.resultado?.data ?? null} erro={leads.resultado?.erro ?? null} carregando={leads.carregando} onClose={() => setModal(null)} />}
    {modal === 'vendas' && <ModalVendas linhas={vendas.resultado?.data ?? null} erro={vendas.resultado?.erro ?? null} carregando={vendas.carregando} onClose={() => setModal(null)} />}
    {modalPendencias && <ModalPendencias key={modalPendencias} grupo={modalPendencias} linhas={pessoasPendencias[modalPendencias].resultado?.data ?? null} erro={pessoasPendencias[modalPendencias].resultado?.erro ?? null} carregando={pessoasPendencias[modalPendencias].carregando} onClose={() => setModalPendencias(null)} />}
  </div>;
}
