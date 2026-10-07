import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { validarFunil } from './funis';
import { CHECKLIST_ATM, MODELOS_FUNIL, MODELOS_PROJETO, chaveProjeto, funilDoModelo, funisDoProjeto, modeloFunil, produtoDoTipo } from './modelos';

const AG_HT = { id: 'ag', nome: 'HT', produto: 'ht' as const, ordem: 1 };

describe('modelos de funil', () => {
  it('todo modelo gera funil válido', () => {
    for (const m of MODELOS_FUNIL) {
      const f = funilDoModelo(m, { agrupadorId: 'ag', produto: 'hm', chave: 'x', prefixoId: m.id });
      expect(validarFunil(f, []), m.id).toEqual([]);
    }
  });
  it('todo projeto aponta para modelos que existem', () => {
    for (const p of MODELOS_PROJETO) for (const id of p.funis) expect(MODELOS_FUNIL.some((m) => m.id === id), `${p.tipo}:${id}`).toBe(true);
  });
  it('chave do projeto no padrão da casa', () => {
    expect(chaveProjeto('HT34 Meteórico · Out/26')).toBe('ht34-meteorico-out-26');
  });
  it('projeto cria os funis com a chave nas campanhas', () => {
    const fs = funisDoProjeto('lancamento_classico', 'Black Friday 26', { id: 'ag', nome: 'HT', produto: 'ht', ordem: 1 }, 'ht');
    expect(fs.map((f) => f.nome)).toEqual([
      'Black Friday 26 · Captação e MQL', 'Black Friday 26 · Venda ativa', 'Black Friday 26 · Checkout e recuperação', 'Black Friday 26 · Recuperação pós-carrinho',
    ]);
    expect(fs.every((f) => f.projeto === 'black-friday-26')).toBe(true);
    expect(fs[1].campanhas[0].regra).toBe('utm_campaign = black-friday-26');
    expect(new Set(fs.flatMap((f) => f.etapas.map((e) => e.id))).size).toBe(fs.reduce((s, f) => s + f.etapas.length, 0));
  });
});

describe('projeto ATM (aula ao vivo de entrada)', () => {
  it('cria a ativação comercial (pré-checkout) e o fechamento da live, com a chave nas campanhas', () => {
    const fs = funisDoProjeto('atm', 'ATM HT out26', AG_HT, 'ht');
    expect(fs.map((f) => f.nome)).toEqual(['ATM HT out26 · Ativação comercial (pré-checkout)', 'ATM HT out26 · Fechamento da live']);
    expect(fs.every((f) => f.projeto === 'atm-ht-out26' && f.produto === 'ht')).toBe(true);
    const [ativ, fech] = fs;
    expect(ativ.tipo).toBe('manual');
    expect(ativ.etapas.map((e) => `${e.nome}:${e.papel}`)).toEqual([
      'Lista recebida:primeiro_contato', 'Contato feito:qualificar', 'Convidado para a live:qualificar', 'Presença confirmada:apresentar_oferta',
      'Ofertado no fechamento:negociar', 'Aguardar pagamento:aguardar_pagamento', 'Fechado na live:fechado',
    ]);
    expect(ativ.campanhas.map((c) => `${c.canal}:${c.nome}`)).toEqual(['disparo:API do caso atm-ht-out26', 'disparo:Base antiga atm-ht-out26', 'formulario:Grupo atm-ht-out26']);
    expect(ativ.campanhas[1].regra).toContain('sem quem reagiu ao último ATM');
    expect(fech.tipo).toBe('hotmart');
    expect(fech.eventosHotmart).toEqual(['carrinho_abandonado', 'cartao_recusado', 'compra_em_aberto']);
    expect(fech.campanhas[0]).toMatchObject({ canal: 'hotmart', nome: 'Oferta da live atm-ht-out26' });
    expect(fech.campanhas[0].regra).toContain('23h59');
  });
  it('serve ao HT e ao Seminário ATM (SV): o produto escolhido vai para os funis', () => {
    expect(funisDoProjeto('atm', 'Seminario ATM nov26', AG_HT, 'sv').every((f) => f.produto === 'sv')).toBe(true);
    expect(produtoDoTipo('atm', 'sv')).toBe('sv');
    expect(produtoDoTipo('atm', 'hm')).toBe('ht');
    expect(produtoDoTipo('seminario', 'hm')).toBe('hm');
  });
  it('checklist com as regras do playbook do ATM', () => {
    const p = MODELOS_PROJETO.find((x) => x.tipo === 'atm')!;
    expect(p.checklist).toBe(CHECKLIST_ATM);
    const texto = p.checklist.join(' | ');
    for (const trecho of ['replay', 'reagiu ao último ATM', 'Seminário', 'D-5', '23h59', '30 a 50 conversas']) expect(texto).toContain(trecho);
  });
  it('o seed do banco (migration do ATM) é o mesmo JSON do front', () => {
    const dir = fileURLToPath(new URL('../../../../infra/supabase/migrations/', import.meta.url));
    const arq = readdirSync(dir).filter((n) => /_crm_projeto_atm\.sql$/.test(n));
    expect(arq).toHaveLength(1);
    const sql = readFileSync(dir + arq[0], 'utf8');
    const q = (s: string) => `'${s.replaceAll("'", "''")}'`;
    for (const id of ['atm_ativacao', 'atm_fechamento']) {
      const m = modeloFunil(id)!;
      expect(sql, id).toContain(`(${q(m.id)}, ${q(m.nome)}, ${q(m.descricao)}, ${q(m.icone)}, ${q(m.tipo)}`);
      expect(sql, id).toContain(`${q(JSON.stringify(m.etapas))}::jsonb, ${q(JSON.stringify(m.campanhas))}::jsonb`);
    }
    const p = MODELOS_PROJETO.find((x) => x.tipo === 'atm')!;
    expect(sql).toContain(`array[${p.funis.map(q).join(',')}]::text[], array[${p.checklist.map(q).join(',')}]::text[]`);
  });
});
