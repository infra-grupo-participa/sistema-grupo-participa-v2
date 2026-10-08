'use client';

// Ponto único de troca da fonte de dados do Comercial (mesmo contrato `ComercialRepository`; nenhuma tela muda).
// NEXT_PUBLIC_COMERCIAL_FONTE=supabase → banco real (F1: só leitura). Ausente/inválido → demonstração em memória.
import { useCallback, useEffect, useRef, useState } from 'react';
import { publicEnv } from '@/shared/infrastructure/config/env';
import type { ComercialRepository } from '../application/ports';
import { idsUnicos } from '../domain/contatos';
import type { Contato } from '../domain/types';
import { ambienteNavegador, criarAtualizador, INTERVALO, INTERVALO_COM_AVISO, JUNTAR_AVISOS_MS, reaproveitar, type Atualizador } from './atualizacao';
import { assinarAvisosCaixa } from '../infrastructure/supabase-avisos-caixa';
import { MockComercialRepository } from '../infrastructure/mock-comercial.repository';
import { SupabaseComercialRepository } from '../infrastructure/supabase-comercial.repository';

export const repo: ComercialRepository = publicEnv.comercialFonte === 'supabase'
  ? new SupabaseComercialRepository()
  : new MockComercialRepository();

/** true enquanto a fonte for a de demonstração (mostra o aviso nas telas). */
export const MODO_DEMONSTRACAO = publicEnv.comercialFonte === 'mock';

// Aviso de mudança: depois de uma escrita, toda tela aberta recarrega o que mostra.
const ouvintes = new Set<() => void>();
export function avisarMudanca() {
  ouvintes.forEach((f) => f());
}

/**
 * Carrega dado do repositório e recarrega quando alguém avisar mudança.
 * `carregar` deve ser estável (useCallback) ou depender só de `deps`.
 * - Requisições numeradas: só a MAIS RECENTE grava (resposta velha que chega depois não pisa na nova).
 * - `carregando`: true até a primeira resposta para os `deps` atuais (troca de contato/filtro), mesmo com dado antigo.
 * - `erro` fica junto com o `dados` anterior: a tela mostra a faixa "Não foi possível atualizar" sem sumir com a lista.
 */
export function useDados<T>(carregar: () => Promise<T>, deps: unknown[] = []) {
  const [dados, setDados] = useState<T | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  // deps (serializado) da última resposta aplicada; diferente da chave atual = carregando.
  const [chaveCarregada, setChaveCarregada] = useState<string | null>(null);
  const vivo = useRef(true);
  const seq = useRef(0);
  // A função mais recente fica num ref; `deps` (serializado) decide quando buscar de novo.
  const fnRef = useRef(carregar);
  useEffect(() => { fnRef.current = carregar; });
  const chave = JSON.stringify(deps);
  const chaveRef = useRef(chave);

  const recarregar = useCallback(async () => {
    const n = ++seq.current;
    const k = chaveRef.current;
    try {
      const d = await fnRef.current();
      if (!vivo.current || n !== seq.current) return;
      // O que não mudou mantém a referência: a busca periódica não pisca a tela nem remonta bolha/mídia.
      setDados((antes) => reaproveitar(antes, d));
      setErro(null);
      setChaveCarregada(k);
    } catch (e) {
      if (!vivo.current || n !== seq.current) return;
      setErro(e instanceof Error ? e.message : 'Não foi possível carregar.');
      setChaveCarregada(k);
    }
  }, []);

  useEffect(() => {
    vivo.current = true;
    chaveRef.current = chave;
    // Busca inicial e assinatura de mudanças (sistema externo).
    recarregar();
    ouvintes.add(recarregar);
    return () => { vivo.current = false; ouvintes.delete(recarregar); };
  }, [recarregar, chave]);

  return { dados, erro, carregando: chaveCarregada !== chave, recarregar };
}

// Sino: recarga só dele (ex.: depois de marcar conversa lida), sem recarregar a tela inteira via avisarMudanca().
const sinos = new Set<() => void>();
/** O sino registra a própria recarga aqui. */
export function useRecargaDoSino(recarregar: () => unknown) {
  useEffect(() => {
    sinos.add(recarregar);
    return () => { sinos.delete(recarregar); };
  }, [recarregar]);
}
export function recarregarSino() {
  sinos.forEach((f) => f());
}

// Atualizadores montados. O aviso do banco (Realtime) cutuca todos de uma vez; o canal só fica aberto enquanto
// houver algum (refcount), e só com o banco real.
const atualizadores = new Set<Atualizador>();
let avisoConectado = false;
let desligarAvisos: (() => void) | null = null;
let juntar: ReturnType<typeof setTimeout> | undefined;

/** Antecipa a busca de toda tela com atualização periódica. */
export function cutucarAtualizacoes() {
  atualizadores.forEach((a) => a.cutucar());
}

// Canal do Realtime: ao trocar de página o último ouvinte sai e o próximo entra logo em seguida. Fechar e reabrir na
// hora dá "tried to subscribe multiple times" (o removeChannel ainda não terminou). Então o canal fica vivo por
// FOLGA_CANAL_MS depois do último ouvinte; quem chega nesse intervalo reaproveita o mesmo canal.
const FOLGA_CANAL_MS = 5_000;
let desligarDepois: ReturnType<typeof setTimeout> | undefined;

function ligarAvisos() {
  clearTimeout(desligarDepois);
  desligarDepois = undefined;
  if (desligarAvisos || MODO_DEMONSTRACAO) return;
  try {
    desligarAvisos = assinarAvisosCaixa(
      () => { clearTimeout(juntar); juntar = setTimeout(cutucarAtualizacoes, JUNTAR_AVISOS_MS); },
      (ok) => {
        // (Re)conectou: busca já, para não perder o que mudou enquanto o canal estava fora.
        if (ok && !avisoConectado) cutucarAtualizacoes();
        avisoConectado = ok;
      },
    );
  } catch { desligarAvisos = null; avisoConectado = false; /* fica só a busca periódica */ }
}

function soltarAvisos() {
  if (atualizadores.size > 0 || !desligarAvisos) return;
  clearTimeout(desligarDepois);
  desligarDepois = setTimeout(() => {
    desligarDepois = undefined;
    if (atualizadores.size > 0 || !desligarAvisos) return;
    const d = desligarAvisos;
    desligarAvisos = null;
    d();
  }, FOLGA_CANAL_MS);
}

/**
 * Atualiza sozinho: busca na hora quando o banco avisa (Realtime) e, de reserva, a cada intervalo do `tipo`
 * (mais curto quando o aviso está fora). Só com `ativo` e a aba visível (oculta = pausa; ao voltar busca na hora).
 * Não sobrepõe chamadas. Regras e carga em `atualizacao.ts`.
 */
export function useAtualizacaoPeriodica(executar: () => Promise<unknown> | unknown, tipo: keyof typeof INTERVALO, ativo = true) {
  const fnRef = useRef(executar);
  useEffect(() => { fnRef.current = executar; });
  useEffect(() => {
    if (!ativo) return;
    const intervalo = () => (avisoConectado ? INTERVALO_COM_AVISO[tipo] : INTERVALO[tipo]);
    const a = criarAtualizador(() => fnRef.current(), intervalo, ambienteNavegador());
    atualizadores.add(a);
    ligarAvisos();
    return () => {
      atualizadores.delete(a);
      a.parar();
      soltarAvisos();
    };
  }, [tipo, ativo]);
}

/**
 * Só os contatos que a tela mostra (ids dos negócios, atividades, conversas…), numa chamada (`crm_contatos_por_ids`),
 * em vez da lista inteira. `ids` nulo = a fonte dos ids ainda está carregando (fica carregando também).
 */
export function useContatosPorIds(ids: (string | null | undefined)[] | null | undefined) {
  const chave = ids ? idsUnicos(ids).sort() : null;
  return useDados<Contato[] | null>(async () => (chave ? repo.contatosPorIds(chave) : null), [chave]);
}

/** Relógio que anda a cada 30 s: os alertas de tempo mudam sem recarregar a página. */
export function useAgora(intervaloMs = 30_000): Date {
  const [agora, setAgora] = useState(() => new Date());
  useEffect(() => {
    const t = setInterval(() => setAgora(new Date()), intervaloMs);
    return () => clearInterval(t);
  }, [intervaloMs]);
  return agora;
}
