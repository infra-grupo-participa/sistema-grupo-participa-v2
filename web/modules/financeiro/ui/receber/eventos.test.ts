// F3 (z67) — sub-aba Eventos: domínio (candidatos, validação, total esperado) e HTML estático da lista, da mini-curva
// e do formulário. Clique, foco e teclado não se provam aqui.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { Eventos, MiniCurva } from './Eventos';
import {
  candidatosReferencia, normalizarEventoPlanejado, totalEsperado, validarEvento, validarMotivoArquivar, type FormEvento,
} from '../../domain/eventos-planejados';
import type { Funil } from '../../domain/funis';

const E = (p: Record<string, unknown> = {}) => normalizarEventoPlanejado({
  id: '7', nome: 'Black Friday', abertura: '2026-10-28', fim_vendas: '2026-11-05', evento_ref_id: '42', evento_ref_nome: 'Acelera 2025',
  evento_ref_abertura: '2025-10-20', evento_ref_venda_ate: '2025-10-28', total_ref: '100000',
  curva: [{ d: 1, liquido: 21000, participacao: 0.21 }, { d: 0, liquido: 70000, participacao: 0.7 }, { d: 2, liquido: 9000, participacao: 0.09 }],
  tamanho_base: '1', tamanho_conservador: '0.7', tamanho_otimista: '1.3', pausa_avulso: true, observacao: null, situacao: 'ativo',
  criado_em: '2026-09-28T10:00:00Z', criado_por_nome: 'Fernanda', atualizado_em: null, atualizado_por_nome: null,
  arquivado_em: null, arquivado_por_nome: null, arquivado_motivo: null, ...p,
});

const F = (p: Partial<Funil>): Funil => ({
  evento_id: 1, nome: 'x', categoria: 'imersao', setor: 'educacao', inicio: '2026-08-01', fim: '2026-08-03', carrinho_inicio: null,
  venda_ate: '2026-08-10', ingresso_de: '', ingressos: 0, ingressos_bruto: 0, ingressos_liquido: 0, oferta_vendas: 0, oferta_compradores: 0,
  oferta_estornos: 0, oferta_bruto: 0, oferta_liquido: 0, compradores: 0, bruto: 0, liquido: 0, ref_vendas: null, ref_valor: null,
  ref_tipo: null, ref_fonte: null, observacao: null, conta_ausente: false, liquido_conferencia: 0, ...p,
});

describe('domínio — eventos planejados', () => {
  it('normaliza números em texto e ordena a curva por dia', () => {
    const e = E();
    expect(e.id).toBe(7);
    expect(e.tamanho_conservador).toBe(0.7);
    expect(e.curva.map((p) => p.d)).toEqual([0, 1, 2]);
    expect(normalizarEventoPlanejado({ curva: null }).curva).toEqual([]);
  });
  it('total esperado = tamanho × total da referência, por cenário; sem venda na referência = null', () => {
    expect(totalEsperado(E(), 'base')).toBe(100000);
    expect(totalEsperado(E(), 'conservador')).toBe(70000);
    expect(totalEsperado(E(), 'otimista')).toBe(130000);
    expect(totalEsperado(E({ total_ref: null }), 'base')).toBeNull();
  });
  it('candidatos: só educação, vendas encerradas e até 31 dias de venda; mais recente primeiro', () => {
    const c = candidatosReferencia([
      F({ evento_id: 1, nome: 'ok antigo', venda_ate: '2026-05-10', inicio: '2026-05-01' }),
      F({ evento_id: 2, nome: 'escritório', setor: 'escritorio' }),
      F({ evento_id: 3, nome: 'ainda vendendo', venda_ate: '2026-09-28' }),
      F({ evento_id: 4, nome: 'longo', inicio: '2026-06-01', venda_ate: '2026-07-02' }), // 31 dias de diferença
      F({ evento_id: 5, nome: 'ok recente', carrinho_inicio: '2026-09-01', inicio: '2026-09-10', venda_ate: '2026-09-27' }),
      F({ evento_id: 6, nome: 'limite 30', inicio: '2026-06-01', venda_ate: '2026-07-01' }),
    ], '2026-09-28');
    expect(c.map((f) => f.evento_id)).toEqual([5, 6, 1]);
  });
  const ok: FormEvento = { nome: 'Black Friday', abertura: '2026-10-28', evento_ref_id: '42', tamanho_conservador: '0,7',
    tamanho_base: '1', tamanho_otimista: '1,3', pausa_avulso: true, observacao: '' };
  it('validação com as regras da RPC; o payload sai com número e observação nula', () => {
    expect(validarEvento(ok, '2026-09-28')).toEqual({ ok: true, entrada: {
      nome: 'Black Friday', abertura: '2026-10-28', evento_ref_id: 42, tamanho_base: 1, tamanho_conservador: 0.7, tamanho_otimista: 1.3,
      pausa_avulso: true, observacao: null } });
    const edit = validarEvento({ ...ok, id: 7 }, '2026-09-28');
    expect(edit.ok && edit.entrada.id).toBe(7);
    const r = validarEvento({ ...ok, nome: ' ', abertura: '2025-01-01', evento_ref_id: '', tamanho_base: '1,5', tamanho_otimista: '1,3' }, '2026-09-28');
    expect(r.ok).toBe(false);
    expect(!r.ok && r.erros).toHaveLength(4);
    expect(validarEvento({ ...ok, tamanho_otimista: '21' }, '2026-09-28').ok).toBe(false);
    expect(validarEvento({ ...ok, abertura: '2026-08-28' }, '2026-09-28').ok).toBe(true); // 31 dias atrás: aceito
    expect(validarEvento({ ...ok, abertura: '2026-08-27' }, '2026-09-28').ok).toBe(false);
  });
  it('motivo de arquivar: 3 a 500', () => {
    expect(validarMotivoArquivar('ab')).not.toBeNull();
    expect(validarMotivoArquivar(' abc ')).toBeNull();
    expect(validarMotivoArquivar('x'.repeat(501))).not.toBeNull();
  });
});

describe('Eventos — HTML', () => {
  const repo = { salvarEventoPlanejado: vi.fn(), arquivarEventoPlanejado: vi.fn() };
  const base = { erro: null, candidatos: null, erroCandidatos: null, hojeISO: '2026-09-28', repo };
  const arquivado = E({ id: 8, nome: 'Evento velho', situacao: 'arquivado', arquivado_em: '2026-09-01T00:00:00Z', arquivado_por_nome: 'Ana',
    arquivado_motivo: 'cancelado' });
  it('lista: referência, tamanhos e venda esperada por cenário; arquivado fora do filtro padrão', () => {
    const h = renderToStaticMarkup(createElement(Eventos, { ...base, eventos: [E(), arquivado], canEdit: true }));
    expect(h).toContain('Black Friday');
    expect(h).toContain('28/10/2026 a 05/11/2026');
    expect(h).toContain('Acelera 2025');
    expect(h).toContain('cons. 0,7× · base 1× · ot. 1,3×');
    expect(h).toMatch(/R\$\s100\.000,00/);
    expect(h).toMatch(/cons\. R\$\s70\.000,00 · base R\$\s100\.000,00 · ot\. R\$\s130\.000,00/);
    expect(h).not.toContain('Evento velho');
    expect(h).toContain('aria-label="Editar: Black Friday"');
    expect(h).toContain('aria-label="Arquivar: Black Friday"');
    expect(h).toContain('Novo evento planejado');
  });
  it('somente leitura: sem Novo/Editar/Arquivar; curva continua disponível', () => {
    const h = renderToStaticMarkup(createElement(Eventos, { ...base, eventos: [E()], canEdit: false }));
    expect(h).toContain('Somente leitura');
    expect(h).not.toContain('Novo evento planejado');
    expect(h).not.toContain('Editar');
    expect(h).toContain('aria-expanded="false"');
    expect(h).toContain('Ver curva');
  });
  it('carregando e erro separados (erro nunca vira lista vazia)', () => {
    expect(renderToStaticMarkup(createElement(Eventos, { ...base, eventos: null, canEdit: true }))).toContain('Carregando eventos planejados');
    const e = renderToStaticMarkup(createElement(Eventos, { ...base, eventos: null, erro: 'Sem permissão.', canEdit: true, onTentarDeNovo: () => {} }));
    expect(e).toContain('role="alert"');
    expect(e).not.toContain('Nenhum evento planejado');
  });
  it('mini-curva: tabela com dia, data no evento planejado, participação em texto e barra decorativa', () => {
    const h = renderToStaticMarkup(createElement(MiniCurva, { e: E() }));
    expect(h).toContain('<caption');
    expect(h).toContain('Curva de Acelera 2025');
    expect(h).toContain('D0');
    expect(h).toContain('28/10/2026'); // D0 = abertura
    expect(h).toContain('30/10/2026'); // D2
    expect(h).toContain('70,0%');
    expect(h).toContain('aria-hidden="true"');
    expect(h).toContain('width:100%');
    expect(h).toContain('width:30%'); // 0,21 ÷ 0,70
    expect(renderToStaticMarkup(createElement(MiniCurva, { e: E({ curva: [] }) }))).toContain('não tem venda por dia');
  });
});
