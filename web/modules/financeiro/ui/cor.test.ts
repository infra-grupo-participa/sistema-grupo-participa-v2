// T2 — o teste que trava o bug que gerou este pedido: card, ficha, barra e
// tabela têm que sair da MESMA origem. Se alguém reintroduzir um mapa
// paralelo (o que causou o board mostrar uma cor e a ficha mostrar outra
// para a mesma pessoa), este teste é o que grita.
import { describe, it, expect } from 'vitest';
import type { StatusFinanceiro } from '../domain/types';
import { corStatus, COR_POR_STATUS, type CorStatus } from '../domain/cor-status';
import { CLASSE_CARD, TONE_BADGE, TONE_BARRA, VAR_COR, statusTone, statusCompraLabel } from './cor';

const TODOS_STATUS = Object.keys(COR_POR_STATUS) as StatusFinanceiro[];

/** Tabela de projeção do plano do arquiteto — a verdade a ser travada. */
const PROJECAO: Record<CorStatus, { classe: string; badge: string; barra: string; var: string }> = {
  verde: { classe: 'gp-card--verde', badge: 'success', barra: 'green', var: 'var(--green)' },
  azul: { classe: 'gp-card--azul', badge: 'info', barra: 'info', var: 'var(--info)' },
  amarelo: { classe: 'gp-card--amarelo', badge: 'warning', barra: 'yellow', var: 'var(--yellow)' },
  vermelho: { classe: 'gp-card--vermelho', badge: 'danger', barra: 'red', var: 'var(--red)' },
  neutro: { classe: 'gp-card--neutro', badge: 'neutral', barra: 'neutral', var: 'var(--border-strong)' },
};

describe('ui/cor — paridade card/ficha/barra/tabela (11 status)', () => {
  it.each(TODOS_STATUS)('%s: CLASSE_CARD, TONE_BADGE e TONE_BARRA batem com a tabela de projeção', (s) => {
    const cor = corStatus(s);
    const esperado = PROJECAO[cor];
    expect(CLASSE_CARD[cor]).toBe(esperado.classe);
    expect(TONE_BADGE[cor]).toBe(esperado.badge);
    expect(TONE_BARRA[cor]).toBe(esperado.barra);
    expect(VAR_COR[cor]).toBe(esperado.var);
  });

  it.each(TODOS_STATUS)('%s: statusTone(s) === TONE_BADGE[corStatus(s)] — o Badge da ficha nunca decide sozinho', (s) => {
    expect(statusTone(s)).toBe(TONE_BADGE[corStatus(s)]);
  });

  it('neutro (status desconhecido) também projeta consistente nas 4 superfícies', () => {
    const cor = corStatus('status_que_o_banco_inventou');
    expect(cor).toBe('neutro');
    expect(CLASSE_CARD[cor]).toBe('gp-card--neutro');
    expect(TONE_BADGE[cor]).toBe('neutral');
    expect(TONE_BARRA[cor]).toBe('neutral');
    expect(statusTone('status_que_o_banco_inventou')).toBe('neutral');
  });

  it('as 5 projeções (CLASSE_CARD/TONE_BADGE/TONE_BARRA/VAR_COR) cobrem as 5 cores, exaustivamente', () => {
    const cores: CorStatus[] = ['verde', 'azul', 'amarelo', 'vermelho', 'neutro'];
    for (const mapa of [CLASSE_CARD, TONE_BADGE, TONE_BARRA, VAR_COR]) {
      expect(Object.keys(mapa).sort()).toEqual([...cores].sort());
    }
  });
});

/** Os status que `public.compras.status` realmente tem em produção, medidos no
 *  Supabase mbvybujpkwuorhtdzcde em 23/08/2026 (com a contagem de cada um).
 *  O dicionário da ficha não pode deixar nenhum deles cair no fallback cru — foi
 *  assim que COMPLETED (171 linhas, o 2º mais frequente) quase subiu para
 *  produção aparecendo em inglês na tela do financeiro. */
const STATUS_REAIS_EM_PRODUCAO = [
  'APPROVED', 'COMPLETED', 'COMPLETE', 'EXPIRED',
  'REFUNDED', 'BILLET_PRINTED', 'CANCELED', 'PROTESTED',
];

describe('statusCompraLabel — ficha nunca mostra status da Hotmart em inglês', () => {
  it.each(STATUS_REAIS_EM_PRODUCAO)('%s tem tradução pt-BR (não cai no fallback cru)', (s) => {
    expect(statusCompraLabel(s)).not.toBe(s);
  });

  it('status desconhecido cai no cru, de propósito — esconder é pior que exibir', () => {
    expect(statusCompraLabel('STATUS_NOVO_DA_HOTMART')).toBe('STATUS_NOVO_DA_HOTMART');
  });
});
