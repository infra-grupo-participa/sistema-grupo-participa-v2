import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import type { EstadoLeitura } from '../application/ultimo-dado';
import type { PendenciaPresencial, PerfilCompradorPresencial } from '../domain/presencial';
import { AbaVisaoVendas } from './AbaVisaoVendas';

const pronto = <T,>(data: T): EstadoLeitura<T> => ({ resultado: { data, erro: null }, carregando: false });

describe('Visão geral de vendas', () => {
  it('mostra parcelas, casamento, total único e pontos temporais pelo contrato', () => {
    const html = renderToStaticMarkup(createElement(AbaVisaoVendas, {
      dias: pronto([]),
      pagamentos: pronto([{ forma: 'CREDIT_CARD', forma_nome: 'Cartão de crédito', parcelas: 12, vendas: 2, receita_bruta: 120 }]),
      perfil: pronto<PerfilCompradorPresencial[]>([
        { dimensao: 'turma', valor: 'T41', compradores: 1 }, { dimensao: 'turma', valor: 'Não é aluno', compradores: 1 },
        { dimensao: 'instrucao', valor: 'THB', compradores: 1 }, { dimensao: 'instrucao', valor: 'Não é aluno', compradores: 1 },
        { dimensao: 'casamento', valor: 'email', compradores: 1 }, { dimensao: 'casamento', valor: 'nao_casou', compradores: 1 },
      ]),
      pendencias: pronto<PendenciaPresencial[]>([
        { grupo: 'nao_pago', categoria: 'boleto', pessoas: 1, transacoes: 1 },
        { grupo: 'nao_pago', categoria: 'pix', pessoas: 1, transacoes: 1 },
        { grupo: 'nao_pago', categoria: 'total', pessoas: 1, transacoes: 2 },
        { grupo: 'cancelada', categoria: 'CANCELLED', pessoas: 1, transacoes: 1 },
        { grupo: 'cancelada', categoria: 'total', pessoas: 1, transacoes: 1 },
      ]),
      serieVendas: pronto([{ dia: '2026-10-07', pre_checkout: 2, vendas: 1, receita_bruta: 120, vendas_acumuladas: 1, receita_acumulada: 120, conversao_pct: 50 }]),
      porHora: pronto([{ hora: 13, vendas: 1, receita_bruta: 120 }]),
      abrirPendencias: () => {},
    }));
    expect(html).toContain('Cartão de crédito · 12x');
    expect(html).toContain('Turma de quem comprou');
    expect(html).toContain('Documento: 0');
    expect(html).toContain('Não é aluno: 1');
    expect(html).toContain('Boleto: 1 · Pix: 1');
    expect(html).toContain('Pessoas únicas sem outra transação paga');
    expect(html).toContain('Vendas e receita acumuladas por dia');
    expect(html).toContain('Conversão por dia');
    expect(html).toContain('13h: 1 vendas');
  });

  it('mantém o dado anterior visível junto do aviso de falha', () => {
    const vazio = pronto([]);
    const html = renderToStaticMarkup(createElement(AbaVisaoVendas, {
      dias: vazio, pagamentos: { resultado: { data: [{ forma: 'PIX', forma_nome: 'Pix', parcelas: 1, vendas: 1, receita_bruta: 10 }], erro: 'Falha de leitura' }, carregando: false },
      perfil: vazio, pendencias: vazio, serieVendas: vazio, porHora: vazio, abrirPendencias: () => {},
    }));
    expect(html).toContain('Falha de leitura');
    expect(html).toContain('Exibindo os últimos dados de formas de pagamento.');
    expect(html).toContain('Pix · 1x');
  });
});
