import { describe, expect, it } from 'vitest';
import type { LinhaTrajetoriaAluno } from './trajetoria-aluno';
import {
  agruparEmMarcos, classificarLinha, duracaoEntre, faixaJornada, mesAno, motivoSaida, posicaoNaRegua,
} from './trajetoria-marcos';
import { marcosFiltrados, paraMarcosVisuais, pontosDaRegua } from '../ui/trajetoria-aluno-itens';

const l = (x: Partial<LinhaTrajetoriaAluno>): LinhaTrajetoriaAluno => ({
  dia: '2024-01-01', momento: null, dimensao: 'vinculo', tipo: 'x', titulo: 't', detalhe: null,
  valor: null, situacao: null, fonte: 'Base de alunos', regra: null, ref: null, ...x,
});

// Caso montado com os tipos medidos no banco (amostra de 250 alunos, 30/09/2026).
const historia: LinhaTrajetoriaAluno[] = [
  l({ dia: '2022-03-10', dimensao: 'vinculo', tipo: 'entrada_thb', titulo: 'Entrada no Time Holding Brasil', detalhe: 'hotmart · indicação' }),
  l({ dia: '2022-03-01', dimensao: 'turma', tipo: 'turma_origem', titulo: 'Turma de origem 12', fonte: 'fin.acoes' }),
  l({ dia: '2022-03-20', dimensao: 'compras', tipo: 'ingresso', titulo: 'Imersão SP', fonte: 'Hotmart', valor: 100 }),
  l({ dia: '2022-03-12', dimensao: 'compras', tipo: 'programa', titulo: 'Holding Masters', fonte: 'Hotmart', valor: 997 }),
  l({ dia: '2022-03-12', dimensao: 'compras', tipo: 'compra', titulo: 'Kit', fonte: 'Hotmart', valor: 50 }),
  l({ dia: '2022-04-01', dimensao: 'eventos', tipo: 'trilha_iniciada', titulo: 'Trilha a nº 1', fonte: 'Central' }),
  l({ dia: '2022-05-01', dimensao: 'eventos', tipo: 'raio_x', titulo: 'Raio-X respondido', fonte: 'Central' }),
  l({ dia: '2022-06-01', dimensao: 'eventos', tipo: 'trilha_encerrada', titulo: 'Trilha a nº 1', fonte: 'Central' }),
  l({ dia: '2022-04-05', dimensao: 'eventos', tipo: 'conta_criada', titulo: 'Conta criada no GPS', fonte: 'GPS' }),
  l({ dia: '2022-07-01', dimensao: 'eventos', tipo: 'atividade_mes', titulo: 'Atividade no GPS em jul/2022', fonte: 'GPS' }),
  l({ dia: '2022-08-01', dimensao: 'eventos', tipo: 'plantao_presenca', titulo: 'Plantão', fonte: 'GPS Plantão' }),
  l({ dia: '2023-01-15', dimensao: 'vinculo', tipo: 'saida', titulo: 'Saída do THB', detalhe: 'Holding Masters', fonte: 'Hotmart', regra: 'estorno/chargeback da compra principal' }),
  l({ dia: '2023-01-15', dimensao: 'compras', tipo: 'estorno', titulo: 'Holding Masters', fonte: 'Hotmart', valor: -997 }),
  l({ dia: '2023-03-01', dimensao: 'eventos', tipo: 'trilha_iniciada', titulo: 'Trilha b nº 2', fonte: 'Central' }),
  l({ dia: '2023-06-01', dimensao: 'vinculo', tipo: 'volta', titulo: 'Volta ao THB', detalhe: 'Holding Masters 2', fonte: 'Hotmart' }),
  l({ dia: '2023-06-01', dimensao: 'compras', tipo: 'programa', titulo: 'Holding Masters 2', fonte: 'Hotmart', valor: 1500 }),
  l({ dia: '2023-07-01', dimensao: 'grupos', tipo: 'entrou_grupo', titulo: 'Entrou no grupo X', fonte: 'WhatsApp (z)' }),
  l({ dia: '2023-08-01', dimensao: 'atendimento', tipo: 'nivel', titulo: 'Nível de resultado', detalhe: 'prata → ouro' }),
];

describe('classificarLinha', () => {
  it('Central e GPS pela fonte; Card HM pela fonte; nível e placa como marco próprio', () => {
    expect(classificarLinha(l({ dimensao: 'eventos', fonte: 'Central' }))).toEqual({ capitulo: 'central' });
    expect(classificarLinha(l({ dimensao: 'eventos', fonte: 'GPS Plantão' }))).toEqual({ capitulo: 'gps' });
    expect(classificarLinha(l({ dimensao: 'eventos', fonte: 'Outra' }))).toEqual({ capitulo: 'eventos' });
    expect(classificarLinha(l({ dimensao: 'atendimento', fonte: 'Card HM', tipo: 'reuniao' }))).toEqual({ capitulo: 'card_hm' });
    expect(classificarLinha(l({ dimensao: 'atendimento', tipo: 'nivel' }))).toEqual({ tipo: 'nivel' });
    expect(classificarLinha(l({ dimensao: 'atendimento', tipo: 'solicitou_placa' }))).toEqual({ tipo: 'placa' });
    expect(classificarLinha(l({ dimensao: 'atendimento', tipo: 'acesso_central' }))).toEqual({ capitulo: 'acesso' });
    expect(classificarLinha(l({ dimensao: 'vinculo', tipo: 'situacao_acesso' }))).toEqual({ capitulo: 'acesso' });
  });
});

describe('agruparEmMarcos', () => {
  const marcos = agruparEmMarcos(historia);
  const porId = (id: string) => marcos.find((m) => m.id === id)!;

  it('do mais antigo ao mais recente; 18 linhas viram 9 marcos', () => {
    expect(marcos.map((m) => m.id)).toEqual([
      'entrada|2022-03-10',
      'compra|2022-03-12',
      'capitulo|central|0',
      'capitulo|gps|0',
      'saida|2023-01-15',
      'capitulo|central|1',
      'volta|2023-06-01',
      'capitulo|grupos|1',
      'nivel|2023-08-01',
    ]);
    expect(marcos.reduce((s, m) => s + m.itens.length, 0)).toBe(historia.length);
  });

  it('entrada agrega turma de origem e ingresso da janela; compras do mesmo dia juntas', () => {
    const e = porId('entrada|2022-03-10');
    expect(e.titulo).toBe('Entrou no time');
    expect(e.tom).toBe('inicio');
    expect(e.itens.map((i) => i.tipo)).toEqual(['turma_origem', 'entrada_thb', 'ingresso']);
    expect(e.resumo).toBe('hotmart · indicação · turma de origem 12 · 1 ingresso');
    expect(e.valor).toBeNull();
    const c = porId('compra|2022-03-12');
    expect(c.titulo).toBe('2 compras no dia');
    expect(c.valor).toBe(1047);
  });

  it('estorno do dia da saída entra no "Saiu"; compra do dia da volta entra no "Voltou"', () => {
    const s = porId('saida|2023-01-15');
    expect(s.titulo).toBe('Saiu do time');
    expect(s.tom).toBe('alerta');
    expect(s.itens.map((i) => i.tipo)).toEqual(['saida', 'estorno']);
    expect(s.resumo).toBe('Holding Masters · estorno da compra principal');
    const v = porId('volta|2023-06-01');
    expect(v.tom).toBe('positivo');
    expect(v.itens.map((i) => i.tipo)).toEqual(['volta', 'programa']);
    expect(marcos.some((m) => m.tipo === 'estorno')).toBe(false);
  });

  it('capítulo: intervalo, resumo humano e corte na saída', () => {
    const c0 = porId('capitulo|central|0');
    expect([c0.inicio, c0.fim]).toEqual(['2022-04-01', '2022-06-01']);
    expect(c0.resumo).toBe('1 trilha · encerrou 1 · Raio-X feito');
    expect(porId('capitulo|central|1').itens).toHaveLength(1);
    expect(porId('capitulo|gps|0').resumo).toBe('conta criada · 1 mês com atividade · 1 plantão (1 com presença)');
    expect(porId('capitulo|grupos|1').resumo).toBe('entrou em 1 grupo');
  });

  it('valor só quando todas as compras do marco têm valor; quem não vê o financeiro (null) fica sem valor', () => {
    const semFin = agruparEmMarcos(historia.map((x) => ({ ...x, valor: null })));
    expect(semFin.every((m) => m.valor == null)).toBe(true);
    expect(paraMarcosVisuais(semFin).flatMap((m) => [m.valor, ...m.itens.map((i) => i.valor)]).every((v) => v == null)).toBe(true);
    const misto = agruparEmMarcos([l({ dimensao: 'compras', tipo: 'compra', valor: 10 }), l({ dimensao: 'compras', tipo: 'compra', valor: null })]);
    expect(misto[0].valor).toBeNull();
  });

  it('sem entrada_thb nem turma de origem: sem marco de entrada; ingresso vira compra; tipo desconhecido não some', () => {
    const m = agruparEmMarcos([
      l({ dia: '2024-01-01', dimensao: 'compras', tipo: 'ingresso', titulo: 'Imersão' }),
      l({ dia: '2024-02-01', dimensao: 'vinculo', tipo: 'novo_tipo', titulo: 'Algo novo' }),
    ]);
    expect(m.map((x) => x.titulo)).toEqual(['Ingresso: Imersão', 'Algo novo']);
  });

  it('ids únicos e vazio', () => {
    expect(new Set(marcos.map((m) => m.id)).size).toBe(marcos.length);
    expect(agruparEmMarcos([])).toEqual([]);
  });

  it('filtro por dimensão agrupa só o que sobrou', () => {
    expect(marcosFiltrados(historia, 'eventos').map((m) => m.id)).toEqual(['capitulo|central|0', 'capitulo|gps|0', 'capitulo|central|1']);
  });
});

describe('faixa, régua e formatos', () => {
  it('mesAno e duração', () => {
    expect(mesAno('2022-03-10')).toBe('mar/2022');
    expect(duracaoEntre('2022-03-10', '2025-09-30')).toBe('3 anos e 6 meses');
    expect(duracaoEntre('2022-03-10', '2023-03-09')).toBe('11 meses');
    expect(duracaoEntre('2022-03-10', '2023-03-10')).toBe('1 ano');
    expect(duracaoEntre('2022-03-10', '2022-03-30')).toBe('menos de 1 mês');
  });

  it('faixa: volta depois da última saída = conta até hoje; saída sem volta = conta até a saída', () => {
    const f = faixaJornada(historia, '2025-09-30');
    expect(f).toMatchObject({ desde: '2022-03-10', fora: false, ate: '2025-09-30', duracao: '3 anos e 6 meses', saidas: 1, voltas: 1 });
    const g = faixaJornada(historia.filter((x) => x.tipo !== 'volta'), '2025-09-30');
    expect(g).toMatchObject({ fora: true, ate: '2023-01-15', duracao: '10 meses' });
  });

  it('régua: só marcos próprios, posição presa a [0,1]', () => {
    expect(posicaoNaRegua('2020-01-01', '2022-01-01', '2024-01-01')).toBe(0);
    expect(posicaoNaRegua('2023-01-01', '2022-01-01', '2024-01-01')).toBeCloseTo(0.5, 2);
    expect(posicaoNaRegua('2022-01-01', '2022-01-01', '2022-01-01')).toBe(0);
    const r = pontosDaRegua(agruparEmMarcos(historia), '2025-09-30')!;
    expect(r.de).toBe('mar/2022');
    expect(r.ate).toBe('set/2025');
    expect(r.pontos).toHaveLength(5);
    expect(r.pontos.every((p) => p.pos >= 0 && p.pos <= 1)).toBe(true);
  });

  it('motivo da saída em português', () => {
    expect(motivoSaida('parcela OVERDUE sem pagamento no contrato em 30 dias')).toBe('parcela sem pagamento por 30 dias');
    expect(motivoSaida(null)).toBeNull();
  });
});
