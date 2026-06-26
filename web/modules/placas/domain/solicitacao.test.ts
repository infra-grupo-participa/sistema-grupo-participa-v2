import { describe, it, expect } from 'vitest';
import {
  computeDisplayStatus,
  getSolicitacaoQueuePriority,
  getSolicitacaoStatusFilterKey,
  isSolicitacaoProcesso,
  isSolicitacaoReenvioPosReprovacao,
  isSolicitacaoSeen,
  REGULARIZACAO_LABEL,
} from './solicitacao';

describe('solicitacao — status de exibição', () => {
  it('status terminais prevalecem sobre auditoria_step', () => {
    expect(computeDisplayStatus({ status: 'concluido', auditoria_step: 2 })).toEqual({
      label: '7/7 · Placa recebida',
      cls: 'sp-entregue',
    });
    expect(computeDisplayStatus({ status: 'placa_postada', auditoria_step: 0 }).label).toBe(
      '7/7 · Placa enviada',
    );
  });

  it('regularização distingue reenvio de aguardando', () => {
    expect(computeDisplayStatus({ regularizacao_pendente: true }).label).toBe(REGULARIZACAO_LABEL);
    expect(
      computeDisplayStatus({ regularizacao_pendente: true, proof_url: 'a', declaracao_url: 'b' })
        .label,
    ).toBe('Reenviou · revisar documentos');
  });

  it('exibe etapa real quando há auditoria_step', () => {
    expect(computeDisplayStatus({ status: 'em_auditoria', auditoria_step: 0 }).label).toBe(
      '1/7 · Documentação em análise',
    );
  });
});

describe('solicitacao — fila/predicados', () => {
  it('regularização tem prioridade máxima na fila', () => {
    expect(getSolicitacaoQueuePriority({ regularizacao_pendente: true, status: 'rejeitado' })).toBe(0);
    expect(getSolicitacaoQueuePriority({ status: 'enviado' })).toBe(1);
  });

  it('isSolicitacaoProcesso exclui rascunho/cadastro/finalizado', () => {
    expect(isSolicitacaoProcesso({ status: 'em_auditoria' })).toBe(true);
    expect(isSolicitacaoProcesso({ status: 'rascunho' })).toBe(false);
    expect(isSolicitacaoProcesso({ status: 'concluido' })).toBe(false);
  });

  it('isReenvioPosReprovacao exige os dois documentos', () => {
    expect(isSolicitacaoReenvioPosReprovacao({ regularizacao_pendente: true, proof_url: 'a' })).toBe(
      false,
    );
    expect(
      isSolicitacaoReenvioPosReprovacao({ regularizacao_pendente: true, proof_url: 'a', declaracao_url: 'b' }),
    ).toBe(true);
  });

  it('statusFilterKey mapeia placa_postada → etapa enviada', () => {
    expect(getSolicitacaoStatusFilterKey({ status: 'placa_postada' })).toBe('audit_5');
    expect(getSolicitacaoStatusFilterKey({ status: 'concluido' })).toBe('audit_6');
  });

  it('isSolicitacaoSeen respeita janela de 5s vs attention', () => {
    const base = '2026-01-01T00:00:00.000Z';
    expect(isSolicitacaoSeen({ admin_seen_at: base, admin_attention_at: base })).toBe(true);
    // attention bem depois do seen → não visto
    expect(
      isSolicitacaoSeen({ admin_seen_at: base, admin_attention_at: '2026-01-02T00:00:00.000Z' }),
    ).toBe(false);
    expect(isSolicitacaoSeen({ admin_seen_at: null })).toBe(false);
  });
});
