import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { traduzirDisparosLista } from '@/modules/infra/atm/infrastructure/atm-data';
import { DisparosDetalhe } from '@/modules/infra/atm/ui/DisparosDetalhe';
import { AbaDisparos } from './AbaDisparos';

const canais = { data: [{ canal: 'whatsapp_api', disparos: 3, enviados: 1200, entregues: 1100, lidas: 800, cliques: 40, falhas: 7, custo_centavos: 15050 }], semDado: false, erro: null };
const lista = { data: traduzirDisparosLista([{ disparo_id: 1, data_hora: '2026-10-08T22:30:00Z', canal: 'whatsapp_api', canal_pago: true, campanha: 'Campanha de teste', tamanho_lista: 1200, entregues: 1100, lidas: 800, cliques: 40, falhas: 7, custo_centavos: 15050 }]), semDado: false, erro: null };

describe('Visão de disparos da Clínica', () => {
  it('mostra as abas dos cinco canais, os sete cards e o disparo da lista', () => {
    const html = renderToStaticMarkup(createElement(AbaDisparos, { canais, lista, carregando: false }));
    for (const rotulo of ['API', 'Grupo', 'SMS', 'Ligação', 'E-mail', 'Disparos', 'Enviados', 'Entregues', 'Lidas / atendidas', 'Cliques', 'Falhas', 'Custo', 'Campanha de teste']) expect(html).toContain(rotulo);
    expect(html).toContain('1.200');
    expect(html).toContain('R$');
  });

  it('canal sem resumo mostra o vazio do ATM, não zero', () => {
    const html = renderToStaticMarkup(createElement(AbaDisparos, { canais: { data: [], semDado: true, erro: null }, lista: { data: [], semDado: true, erro: null }, carregando: false }));
    expect(html).toContain('Sem dados para este canal');
    expect(html).not.toContain('>0<');
  });

  it('antes da primeira leitura mostra carregando', () => {
    expect(renderToStaticMarkup(createElement(AbaDisparos, { canais: null, lista: null, carregando: true }))).toContain('Carregando disparos');
  });

  // NÃO são linhas lidas do banco: neste ambiente não há sessão da equipe nem service role. Os números são os medidos em produção
  // e anotados em infra/supabase/migrations/20261017020500.explain.md (passo 20) e em docs/dashboard-presencial.md §2.13.2.
  const medido = {
    data: [
      { canal: 'whatsapp_api', disparos: 2, enviados: 2945, entregues: null, lidas: null, cliques: null, falhas: null, custo_centavos: null },
      { canal: 'grupo', disparos: 0, enviados: 0, entregues: 0, lidas: 0, cliques: 0, falhas: 0, custo_centavos: null },
      { canal: 'sms', disparos: 0, enviados: 0, entregues: 0, lidas: 0, cliques: 0, falhas: 0, custo_centavos: null },
      { canal: 'ligacao', disparos: 0, enviados: 0, entregues: 0, lidas: 0, cliques: 0, falhas: 0, custo_centavos: null },
      { canal: 'email', disparos: 5, enviados: 7827, entregues: 7814, lidas: 1078, cliques: 23, falhas: 13, custo_centavos: null },
    ],
    semDado: false, erro: null,
  };
  const vazia = { data: [], semDado: false, erro: null };

  it('API com os totais medidos: 2 disparos, 2.945 enviados e o resto Sem dado', () => {
    const html = renderToStaticMarkup(createElement(AbaDisparos, { canais: medido, lista: vazia, carregando: false, canalInicial: 'api' }));
    expect(html).toContain('2.945');
    expect(html.match(/Sem dado/g)?.length).toBe(5);
    expect(html).toContain('Nenhum disparo registrado');
    expect(html).not.toContain('no período');
  });

  it('E-mail com os totais medidos: 5, 7.827, 7.814, 1.078, 23 e 13', () => {
    const html = renderToStaticMarkup(createElement(AbaDisparos, { canais: medido, lista: vazia, carregando: false, canalInicial: 'email' }));
    for (const n of ['5', '7.827', '7.814', '1.078', '23', '13']) expect(html).toContain(`>${n}<`);
    expect(html.match(/Sem dado/g)?.length).toBe(1);
  });

  it('Grupo, SMS e Ligação com 0 mostram 0, e só o Custo fica Sem dado', () => {
    for (const canalInicial of ['grupo', 'sms', 'ligacao'] as const) {
      const html = renderToStaticMarkup(createElement(AbaDisparos, { canais: medido, lista: vazia, carregando: false, canalInicial }));
      expect(html.match(/>0</g)?.length).toBe(6);
      expect(html.match(/Sem dado/g)?.length).toBe(1);
    }
  });

  it('ATM e Black seguem dizendo "no período" (o texto novo só vale com semFiltroPeriodo)', () => {
    const html = renderToStaticMarkup(createElement(DisparosDetalhe, { result: { data: [], semDado: false, erro: null }, canal: 'email' }));
    expect(html).toContain('Nenhum disparo no período');
  });
});
