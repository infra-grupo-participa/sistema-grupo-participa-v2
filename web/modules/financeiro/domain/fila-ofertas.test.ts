import { describe, expect, it } from 'vitest';
import {
  argsDecidirOferta, formDaProposta, normalizarOfertaFila, novoEventoDoForm, rotuloOferta, validarNovoEvento,
} from './fila-ofertas';

describe('normalizarOfertaFila', () => {
  it('bigint em texto vira número; datas cortadas; proposta lida (objeto ou texto)', () => {
    const o = normalizarOfertaFila({ oferta_codigo: 'abc', oferta_nome: '', n_vendas: '5', sugestao_evento_id: '412',
      primeira_venda: '2026-09-01T00:00:00', ultima_venda: null,
      proposta_evento: '{"nome":"X","categoria":"clinica","carrinho_inicio":"2026-09-01","venda_ate":"2026-09-20"}' });
    expect(o).toMatchObject({ oferta_codigo: 'abc', oferta_nome: null, n_vendas: 5, sugestao_evento_id: 412,
      primeira_venda: '2026-09-01', ultima_venda: null });
    expect(o.proposta_evento).toEqual({ nome: 'X', categoria: 'clinica', carrinho_inicio: '2026-09-01', venda_ate: '2026-09-20' });
    expect(rotuloOferta(o)).toBe('abc');
  });
  it('sugestão ausente = null (nunca 0); proposta inválida = null', () => {
    const o = normalizarOfertaFila({ oferta_codigo: 'a', sugestao_evento_id: null, proposta_evento: '[1]' });
    expect(o.sugestao_evento_id).toBeNull();
    expect(o.proposta_evento).toBeNull();
  });
});

describe('argsDecidirOferta — exatamente uma ação', () => {
  it('confirmar', () => expect(argsDecidirOferta('a', { tipo: 'confirmar', eventoId: 7 })).toEqual({ p_oferta: 'a', p_evento_id: 7 }));
  it('rejeitar', () => expect(argsDecidirOferta('a', { tipo: 'rejeitar' })).toEqual({ p_oferta: 'a', p_rejeitar: true }));
  it('criar: sem chaves vazias, categoria em minúsculas', () => {
    expect(argsDecidirOferta('a', { tipo: 'criar', evento: { nome: ' Clínica ', categoria: 'Clinica', inicio: '2026-10-01' } }))
      .toEqual({ p_oferta: 'a', p_criar: { nome: 'Clínica', categoria: 'clinica', inicio: '2026-10-01' } });
  });
});

describe('formulário Criar evento', () => {
  const o = normalizarOfertaFila({ oferta_codigo: 'a', oferta_nome: 'Oferta', produto_nome: 'P',
    proposta_evento: { nome: 'Clínica POA', categoria: 'clinica', carrinho_inicio: '2026-09-10', venda_ate: '2026-09-25' } });
  it('pré-preenche com a proposta; data do evento fica em branco', () => {
    expect(formDaProposta(o)).toEqual({ nome: 'Clínica POA', categoria: 'clinica', inicio: '', fim: '',
      carrinho_inicio: '2026-09-10', venda_ate: '2026-09-25' });
  });
  it('proposta com inicio (z95): formulário vem com a data da 1ª venda', () => {
    const c = normalizarOfertaFila({ oferta_codigo: 'a', proposta_evento: { nome: 'X', categoria: 'clinica', inicio: '2026-09-27' } });
    expect(c.proposta_evento?.inicio).toBe('2026-09-27');
    expect(formDaProposta(c).inicio).toBe('2026-09-27');
    const t = normalizarOfertaFila({ oferta_codigo: 'a', proposta_evento: '{"nome":"X","inicio":"2026-09-27"}' });
    expect(formDaProposta(t).inicio).toBe('2026-09-27');
  });
  it('proposta antiga sem inicio: campo vazio', () => {
    expect(o.proposta_evento).not.toHaveProperty('inicio');
    expect(formDaProposta(o).inicio).toBe('');
  });
  it('inicio inválido: campo vazio', () => {
    for (const inicio of ['27/09/2026', '2026-9-7', '2026-13-45', '', null, 20260927, 'lixo']) {
      const c = normalizarOfertaFila({ oferta_codigo: 'a', proposta_evento: { nome: 'X', inicio } });
      expect(formDaProposta(c).inicio).toBe('');
    }
  });
  it('sem proposta: nome da oferta, resto vazio', () => {
    expect(formDaProposta({ ...o, proposta_evento: null })).toMatchObject({ nome: 'Oferta', categoria: '', carrinho_inicio: '' });
  });
  it('mesmas travas da RPC', () => {
    const f = formDaProposta(o);
    expect(validarNovoEvento(f)).toEqual(['Informe a data do evento.']);
    expect(validarNovoEvento({ ...f, inicio: '2026-09-27' })).toEqual([]);
    expect(validarNovoEvento({ ...f, inicio: '2026-09-27', fim: '2026-09-26' })).toContain('O fim do evento não pode ser antes do início.');
    expect(validarNovoEvento({ ...f, inicio: '2026-09-27', carrinho_inicio: '2026-09-30' }))
      .toContain('A abertura das vendas não pode ser depois do fim das vendas.');
    expect(validarNovoEvento({ ...f, inicio: '2026-09-27', categoria: 'Clínica POA' })).toHaveLength(1);
    expect(validarNovoEvento({ ...f, inicio: '2026-09-27', nome: '  ' })).toHaveLength(1);
  });
  it('novoEventoDoForm omite opcionais vazios', () => {
    const ev = novoEventoDoForm({ ...formDaProposta(o), inicio: '2026-09-27', venda_ate: '' });
    expect(argsDecidirOferta('a', { tipo: 'criar', evento: ev }))
      .toEqual({ p_oferta: 'a', p_criar: { nome: 'Clínica POA', categoria: 'clinica', inicio: '2026-09-27', carrinho_inicio: '2026-09-10' } });
  });
});
