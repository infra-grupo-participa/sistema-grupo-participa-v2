import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  agendaAtivacao, avisoCarga, avisoMensageria, datasDoEvento, diasDoEvento, emExpediente, MODELO_ATIVACAO, mencionaReplay,
  nivelCarga, preencherRoteiro, proximoExpediente, ROTEIROS_ATIVACAO, sextaAnterior, validarAtivacao, type EdicaoAtivacao,
} from './ativacao';
import { validarFunil } from './funis';
import { funilDoModelo, funisDoProjeto, MODELOS_PROJETO } from './modelos';

const br = (s: string) => new Date(`${s}-03:00`);
const AG = { id: 'ag', nome: 'HT', produto: 'ht' as const, ordem: 1 };

describe('modelo do funil de Ativação', () => {
  it('é um funil válido, com a entrada no prazo de primeiro contato (5/15 min) e Ganho só no fim', () => {
    const f = funilDoModelo(MODELO_ATIVACAO, { agrupadorId: 'ag', produto: 'ht', chave: 'x', prefixoId: 'a' });
    expect(validarFunil(f, [])).toEqual([]);
    expect(f.etapas[0]).toMatchObject({ papel: 'primeiro_contato', slaAtencaoMin: 5, slaCriticoMin: 15 });
    expect(f.etapas.map((e) => e.nome)).toEqual(['Toque 1: falar agora', 'Salvou o número', 'Ligação feita', 'Presença confirmada', 'Compareceu', 'Comprou']);
    expect(f.etapas.at(-1)?.papel).toBe('fechado');
  });

  it('todo tipo de projeto ganha a Ativação como primeiro funil, sem "Captação e MQL" duplicando', () => {
    for (const p of MODELOS_PROJETO) {
      const fs = funisDoProjeto(p.tipo, 'Proj X', AG, 'ht');
      expect(fs[0].nome, p.tipo).toBe('Proj X · Ativação');
      expect(fs.filter((f) => f.nome.endsWith('· Ativação')), p.tipo).toHaveLength(1);
      expect(fs.some((f) => f.nome.endsWith('Captação e MQL')), p.tipo).toBe(false);
    }
  });

  it('o seed do banco (migration 20261007135415) é o mesmo JSON do front', () => {
    const arq = fileURLToPath(new URL('../../../../infra/supabase/migrations/20261007135415_crm_ativacao_padrao.sql', import.meta.url));
    const sql = readFileSync(arq, 'utf8');
    const q = (s: string) => `'${s.replaceAll("'", "''")}'`;
    const m = MODELO_ATIVACAO;
    expect(sql).toContain(`(${q(m.id)}, ${q(m.nome)}, ${q(m.descricao)}, ${q(m.icone)}, ${q(m.tipo)}, '{}'::text[], ${q(JSON.stringify(m.etapas))}::jsonb, ${q(JSON.stringify(m.campanhas))}::jsonb, 0)`);
    // a regra de entrada é contrato com a catalogação de origem
    expect(sql).toContain('create function crm.projeto_do_evento(p_fonte text, p_dados jsonb) returns text');
  });
});

describe('horário comercial (seg–sex 8h–20h, sáb 9h–13h, domingo e feriado fechados)', () => {
  it('dentro do expediente é agora; fora, a abertura do próximo', () => {
    expect(proximoExpediente(br('2026-10-14T10:00:00')).toISOString()).toBe(br('2026-10-14T10:00:00').toISOString());
    expect(proximoExpediente(br('2026-10-13T07:00:00')).toISOString()).toBe(br('2026-10-13T08:00:00').toISOString());
    expect(proximoExpediente(br('2026-10-16T21:00:00')).toISOString()).toBe(br('2026-10-17T09:00:00').toISOString()); // sex → sáb 9h
    expect(proximoExpediente(br('2026-10-10T14:00:00')).toISOString()).toBe(br('2026-10-13T08:00:00').toISOString()); // sáb tarde → ter (12/10 feriado)
    expect(proximoExpediente(br('2026-10-18T10:00:00')).toISOString()).toBe(br('2026-10-19T08:00:00').toISOString()); // domingo → seg
    expect(proximoExpediente(br('2026-10-12T10:00:00')).toISOString()).toBe(br('2026-10-13T08:00:00').toISOString()); // feriado → ter
    expect(emExpediente(br('2026-10-17T12:59:00'))).toBe(true);
    expect(emExpediente(br('2026-10-17T13:00:00'))).toBe(false);
  });
});

describe('agenda dos três toques', () => {
  it('sexta anterior: evento na segunda → sexta antes; evento na sexta → a da semana anterior', () => {
    expect(sextaAnterior('2026-10-26')).toBe('2026-10-23');
    expect(sextaAnterior('2026-10-23')).toBe('2026-10-16');
    expect(sextaAnterior('2026-10-25')).toBe('2026-10-23');
  });

  it('toque 1 na hora, toque 2 na sexta às 10h, toque 3 em cada dia 1 h antes', () => {
    const t = agendaAtivacao(br('2026-10-07T10:00:00'), { eventoInicio: '2026-10-26', eventoFim: '2026-10-28', eventoHora: '19:00' });
    expect(t.map((x) => x.toque)).toEqual(['toque1', 'toque2', 'toque3', 'toque3', 'toque3']);
    expect(t[0]).toMatchObject({ tipo: 'whatsapp', titulo: 'Toque 1: mensagem agora (salvar o número)' });
    expect(t[0].venceEm.toISOString()).toBe(br('2026-10-07T10:00:00').toISOString());
    expect(t[1]).toMatchObject({ tipo: 'ligacao', titulo: 'Toque 2: ligar (5 blocos)' });
    expect(t[1].venceEm.toISOString()).toBe(br('2026-10-23T10:00:00').toISOString());
    expect(t[2].venceEm.toISOString()).toBe(br('2026-10-26T18:00:00').toISOString());
    expect(t[4].titulo).toBe('Toque 3 · dia 3: link no privado antes do grupo');
  });

  it('entrada à noite: o toque 1 vence na abertura do expediente', () => {
    const t = agendaAtivacao(br('2026-10-07T22:30:00'), { eventoInicio: null, eventoFim: null, eventoHora: null });
    expect(t).toHaveLength(1);
    expect(t[0].venceEm.toISOString()).toBe(br('2026-10-08T08:00:00').toISOString());
  });

  it('entrou depois da sexta: ligação no próximo expediente; dia que já passou não entra', () => {
    const t = agendaAtivacao(br('2026-10-24T15:00:00'), { eventoInicio: '2026-10-26', eventoFim: '2026-10-26', eventoHora: null }); // sábado à tarde
    expect(t.find((x) => x.toque === 'toque2')?.venceEm.toISOString()).toBe(br('2026-10-26T08:00:00').toISOString());
    expect(t.find((x) => x.toque === 'toque3')?.venceEm.toISOString()).toBe(br('2026-10-26T09:00:00').toISOString());
    const noEvento = agendaAtivacao(br('2026-10-27T10:00:00'), { eventoInicio: '2026-10-26', eventoFim: '2026-10-28', eventoHora: '19:00' });
    expect(noEvento.filter((x) => x.toque === 'toque3')).toHaveLength(2);
    expect(noEvento.some((x) => x.toque === 'toque2')).toBe(false);
  });

  it('dias do evento: até 7', () => {
    expect(diasDoEvento('2026-10-26', '2026-10-28')).toEqual(['2026-10-26', '2026-10-27', '2026-10-28']);
    expect(diasDoEvento('2026-10-26', null)).toEqual(['2026-10-26']);
  });
});

describe('teto da Meta e régua da Mensageria', () => {
  it('teto de 50 conversas novas por número (atenção a partir de 40)', () => {
    expect(nivelCarga(39)).toBe('ok');
    expect(nivelCarga(40)).toBe('atencao');
    expect(nivelCarga(50)).toBe('atencao');
    expect(nivelCarga(51)).toBe('acima');
    expect(avisoCarga({ novasHoje: 10 }, 'Ana')).toBeNull();
    expect(avisoCarga({ novasHoje: 55 }, 'Ana')).toContain('passou do teto de 50');
  });
  it('avisa colisão com disparo da Mensageria no mesmo dia', () => {
    expect(avisoMensageria({ mensageriaHoje: 0, nome: 'X' })).toBeNull();
    expect(avisoMensageria({ mensageriaHoje: 2, nome: 'HT34' })).toContain('mesmo dia');
  });
});

describe('cadastro e roteiros', () => {
  const base: EdicaoAtivacao = { projeto: 'p', eventoInicio: '2026-10-26', eventoFim: '2026-10-28', eventoHora: '19:00', carrinhoFim: '2026-10-30', hotmartOferta: ['5064314'], ligado: true };
  it('valida como o banco', () => {
    expect(validarAtivacao(base)).toBeNull();
    expect(validarAtivacao({ ...base, eventoFim: null })).toContain('início e o fim');
    expect(validarAtivacao({ ...base, eventoFim: '2026-10-20' })).toContain('antes do início');
    expect(validarAtivacao({ ...base, eventoFim: '2026-11-05' })).toBe('Evento de até 7 dias.');
    expect(validarAtivacao({ ...base, hotmartOferta: ['abc'] })).toContain('número do produto');
    expect(validarAtivacao({ ...base, eventoInicio: null, eventoFim: null })).toContain('precisa da data');
    expect(validarAtivacao({ ...base, eventoInicio: null, eventoFim: null, ligado: false })).toBeNull();
    expect(validarAtivacao({ ...base, carrinhoFim: '2026-10-20' })).toContain('carrinho não fecha');
  });
  it('roteiros: preenche o que veio, deixa [x] para completar e nunca falam de replay', () => {
    const t = preencherRoteiro(ROTEIROS_ATIVACAO[0].texto, { vendedor: 'Ana', especialista: 'Prof. Marcio', datas: '26 a 28/10' });
    expect(t).toContain('Aqui é o Ana, da equipe do Prof. Marcio');
    expect(t).toContain('[nome]');
    expect(t).toContain('salva o meu número');
    for (const r of ROTEIROS_ATIVACAO) expect(mencionaReplay(r.texto), r.id).toBe(false);
    expect(mencionaReplay('vai ter replay amanhã')).toBe(true);
  });
  it('datas legíveis', () => {
    expect(datasDoEvento('2026-10-26', '2026-10-28')).toBe('26 a 28/10');
    expect(datasDoEvento('2026-10-31', '2026-11-02')).toBe('31/10 a 02/11');
    expect(datasDoEvento(null, null)).toBe('');
  });
});
