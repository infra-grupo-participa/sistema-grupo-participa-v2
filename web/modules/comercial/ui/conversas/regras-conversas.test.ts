import { describe, expect, it } from 'vitest';
import { criarTravaEnvio, esperaResposta, janelaRestante, minutosUteis, ordenarConversas, preencherTemplate, resumoCaixa, rotuloDia, temEmoji } from './regras-conversas';

// 05/10/2026 é segunda-feira.
const seg = (h: number, m = 0) => new Date(2026, 9, 5, h, m);

describe('minutosUteis', () => {
  it('conta só dentro do expediente', () => {
    expect(minutosUteis(seg(10), seg(10, 30))).toBe(30);
    expect(minutosUteis(seg(7), seg(8, 10))).toBe(10);
    expect(minutosUteis(seg(19, 50), seg(21))).toBe(10);
  });
  it('domingo não conta', () => {
    expect(minutosUteis(new Date(2026, 9, 4, 10), new Date(2026, 9, 4, 18))).toBe(0);
  });
  it('atravessa a noite', () => {
    // sex 19h50 → sáb 9h05 = 10 + 5
    expect(minutosUteis(new Date(2026, 9, 9, 19, 50), new Date(2026, 9, 10, 9, 5))).toBe(15);
  });
});

describe('esperaResposta', () => {
  it('só quando a última mensagem é do lead', () => {
    expect(esperaResposta({ direcao: 'saida', em: seg(10).toISOString() }, seg(11))).toBeNull();
  });
  it('5 min atenção, 15 min crítico', () => {
    const em = seg(10).toISOString();
    expect(esperaResposta({ direcao: 'entrada', em }, seg(10, 3))?.nivel).toBe('ok');
    expect(esperaResposta({ direcao: 'entrada', em }, seg(10, 6))?.nivel).toBe('atencao');
    expect(esperaResposta({ direcao: 'entrada', em }, seg(10, 20))?.nivel).toBe('critico');
  });
  it('fora do horário comercial não estoura o alerta', () => {
    const r = esperaResposta({ direcao: 'entrada', em: seg(22).toISOString() }, seg(23, 30));
    expect(r?.minutos).toBe(90);
    expect(r?.nivel).toBe('ok');
  });
});

describe('janelaRestante', () => {
  it('fechada quando nula ou vencida', () => {
    expect(janelaRestante(null, seg(10))).toBeNull();
    expect(janelaRestante(seg(9).toISOString(), seg(10))).toBeNull();
  });
  it('formata horas e minutos', () => {
    expect(janelaRestante(seg(15, 12).toISOString(), seg(10))?.rotulo).toBe('5h 12min');
    expect(janelaRestante(seg(10, 42).toISOString(), seg(10))?.rotulo).toBe('42 min');
  });
});

describe('preencherTemplate', () => {
  it('preenche e aponta o que falta', () => {
    const r = preencherTemplate('Oi {{nome}}, aqui é {{vendedor}} sobre o {{evento}}.', { nome: 'Ana', vendedor: 'Ronan' });
    expect(r.texto).toBe('Oi Ana, aqui é Ronan sobre o {{evento}}.');
    expect(r.faltando).toEqual(['evento']);
  });
});

describe('rotuloDia e emoji', () => {
  it('hoje e ontem', () => {
    expect(rotuloDia(seg(8).toISOString(), seg(20))).toBe('Hoje');
    expect(rotuloDia(new Date(2026, 9, 4, 23).toISOString(), seg(1))).toBe('Ontem');
  });
  it('detecta emoji', () => {
    expect(temEmoji('Oi, tudo bem? 🙂')).toBe(true);
    expect(temEmoji('Oi, tudo bem?')).toBe(false);
  });
});

describe('ordenarConversas', () => {
  const cv = (id: string, direcao: 'entrada' | 'saida', em: Date, naoLidas = 0) => ({
    id, naoLidas, ultimaMensagem: { direcao, em: em.toISOString() },
  });
  const agora = seg(11);

  it('crítico, depois atenção, depois o resto pela última mensagem', () => {
    const lista = [
      cv('respondida-recente', 'saida', seg(10, 58)),
      cv('atencao', 'entrada', seg(10, 50), 1),
      cv('respondida-antiga', 'saida', seg(9)),
      cv('critico', 'entrada', seg(10, 30), 2),
      cv('acabou-de-chegar', 'entrada', seg(10, 59), 1),
    ];
    expect(ordenarConversas(lista, agora).map((c) => c.id)).toEqual([
      'critico', 'atencao', 'acabou-de-chegar', 'respondida-recente', 'respondida-antiga',
    ]);
  });

  it('entre críticos, quem espera há mais tempo vem primeiro', () => {
    const lista = [cv('20min', 'entrada', seg(10, 40)), cv('1h', 'entrada', seg(10))];
    expect(ordenarConversas(lista, agora).map((c) => c.id)).toEqual(['1h', '20min']);
  });

  it('não muda a lista original', () => {
    const lista = [cv('a', 'saida', seg(9)), cv('b', 'saida', seg(10))];
    ordenarConversas(lista, agora);
    expect(lista.map((c) => c.id)).toEqual(['a', 'b']);
  });
});

describe('resumoCaixa', () => {
  const msg = (direcao: 'entrada' | 'saida', em: Date) => ({ direcao, em: em.toISOString() }) as never;
  it('conta espera, crítico, não lidas e sem dono', () => {
    const agora = seg(11);
    const r = resumoCaixa([
      { naoLidas: 2, atribuidaA: 'v1', ultimaMensagem: msg('entrada', seg(10)) },
      { naoLidas: 1, atribuidaA: null, ultimaMensagem: msg('entrada', seg(10, 57)) },
      { naoLidas: 0, atribuidaA: null, ultimaMensagem: msg('saida', seg(9)) },
    ], agora);
    expect(r).toEqual({ esperando: 2, criticas: 1, naoLidas: 3, semDono: 2 });
  });
  it('lista vazia zera tudo', () => {
    expect(resumoCaixa([], seg(11))).toEqual({ esperando: 0, criticas: 0, naoLidas: 0, semDono: 0 });
  });
});

describe('criarTravaEnvio', () => {
  const gerador = () => { let n = 0; return () => `k${++n}`; };
  it('só um envio em voo: o segundo clique é ignorado', () => {
    const t = criarTravaEnvio(gerador());
    expect(t.comecar('oi')).toBe('k1');
    expect(t.comecar('oi')).toBeNull();
    expect(t.emVoo()).toBe(true);
    t.terminar(true);
    expect(t.emVoo()).toBe(false);
  });
  it('falhou com o mesmo conteúdo: a chave se mantém (retry não duplica no banco)', () => {
    const t = criarTravaEnvio(gerador());
    expect(t.comecar('oi')).toBe('k1');
    t.terminar(false);
    expect(t.comecar('oi')).toBe('k1');
  });
  it('mudou o conteúdo ou deu certo: chave nova', () => {
    const t = criarTravaEnvio(gerador());
    t.comecar('oi'); t.terminar(false);
    expect(t.comecar('oi, tudo bem?')).toBe('k2');
    t.terminar(true);
    expect(t.comecar('oi, tudo bem?')).toBe('k3');
  });
});
