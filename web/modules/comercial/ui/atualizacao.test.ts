import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { chamadasPorMinuto, criarAtualizador, estaNoFim, INTERVALO, INTERVALO_COM_AVISO, reaproveitar, type AmbienteAtualizacao } from './atualizacao';

function ambiente() {
  let visivel = true;
  const voltar = new Set<() => void>();
  const ocultar = new Set<() => void>();
  const amb: AmbienteAtualizacao = {
    visivel: () => visivel,
    aoVoltar: (cb) => { voltar.add(cb); return () => voltar.delete(cb); },
    aoOcultar: (cb) => { ocultar.add(cb); return () => ocultar.delete(cb); },
    setTimeout: (cb, ms) => setTimeout(cb, ms),
    clearTimeout: (id) => clearTimeout(id as ReturnType<typeof setTimeout>),
    agora: () => Date.now(),
  };
  return {
    amb,
    ocultar() { visivel = false; ocultar.forEach((f) => f()); },
    mostrar() { visivel = true; voltar.forEach((f) => f()); },
    ouvintes: () => voltar.size + ocultar.size,
  };
}

describe('criarAtualizador', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('busca a cada intervalo', async () => {
    const f = vi.fn();
    const a = criarAtualizador(f, 3_000, ambiente().amb);
    await vi.advanceTimersByTimeAsync(2_999);
    expect(f).toHaveBeenCalledTimes(0);
    await vi.advanceTimersByTimeAsync(1);
    expect(f).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(9_000);
    expect(f).toHaveBeenCalledTimes(4);
    a.parar();
  });

  it('pausa com a aba oculta e busca na hora ao voltar', async () => {
    const f = vi.fn();
    const e = ambiente();
    const a = criarAtualizador(f, 3_000, e.amb);
    await vi.advanceTimersByTimeAsync(3_000);
    expect(f).toHaveBeenCalledTimes(1);
    e.ocultar();
    await vi.advanceTimersByTimeAsync(60_000);
    expect(f).toHaveBeenCalledTimes(1);
    e.mostrar();
    await vi.advanceTimersByTimeAsync(0);
    expect(f).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(3_000);
    expect(f).toHaveBeenCalledTimes(3);
    a.parar();
  });

  it('ocultar e voltar dentro da folga não para o laço', async () => {
    const f = vi.fn();
    const e = ambiente();
    const a = criarAtualizador(f, 3_000, e.amb);
    await vi.advanceTimersByTimeAsync(3_000);
    expect(f).toHaveBeenCalledTimes(1);
    // some e volta logo depois da busca (dentro da folga de 1 s): não busca na hora...
    e.ocultar();
    await vi.advanceTimersByTimeAsync(200);
    e.mostrar();
    await vi.advanceTimersByTimeAsync(0);
    expect(f).toHaveBeenCalledTimes(1);
    // ...mas o próximo ciclo continua agendado
    await vi.advanceTimersByTimeAsync(3_000);
    expect(f).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(3_000);
    expect(f).toHaveBeenCalledTimes(3);
    a.parar();
  });

  it('não sobrepõe chamadas lentas e não perde o pedido feito no meio', async () => {
    let soltar: () => void = () => {};
    const f = vi.fn(() => new Promise<void>((r) => { soltar = r; }));
    const a = criarAtualizador(f, 1_000, ambiente().amb);
    await vi.advanceTimersByTimeAsync(1_000);
    expect(f).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(5_000);
    a.cutucar();
    expect(f).toHaveBeenCalledTimes(1); // ainda em voo
    soltar();
    await vi.advanceTimersByTimeAsync(0);
    expect(f).toHaveBeenCalledTimes(2); // o pedido pendente roda assim que a anterior termina
    a.parar();
  });

  it('rajada de cutucões (foco + visibilidade + Realtime): no máximo a busca + uma de garantia', async () => {
    const f = vi.fn();
    const a = criarAtualizador(f, 10_000, ambiente().amb);
    await vi.advanceTimersByTimeAsync(5_000);
    a.cutucar(); a.cutucar(); a.cutucar(); a.cutucar();
    await vi.advanceTimersByTimeAsync(0);
    expect(f).toHaveBeenCalledTimes(2);
    // logo depois (dentro da folga) não busca de novo
    a.cutucar();
    await vi.advanceTimersByTimeAsync(0);
    expect(f).toHaveBeenCalledTimes(2);
    a.parar();
  });

  it('intervalo dinâmico: afrouxa quando o aviso do banco conecta, aperta quando cai', async () => {
    const f = vi.fn();
    let conectado = false;
    const a = criarAtualizador(f, () => (conectado ? INTERVALO_COM_AVISO.conversaAberta : INTERVALO.conversaAberta), ambiente().amb);
    await vi.advanceTimersByTimeAsync(3_000);
    expect(f).toHaveBeenCalledTimes(1);
    conectado = true; // vale a partir do próximo agendamento (já marcado para +3 s)
    await vi.advanceTimersByTimeAsync(3_000);
    expect(f).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(14_999);
    expect(f).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(1);
    expect(f).toHaveBeenCalledTimes(3);
    a.parar();
  });

  it('erro na busca não para o laço', async () => {
    const f = vi.fn().mockRejectedValueOnce(new Error('rede')).mockResolvedValue(undefined);
    const a = criarAtualizador(f, 1_000, ambiente().amb);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(f).toHaveBeenCalledTimes(2);
    a.parar();
  });

  it('parar cancela o timer e solta os ouvintes', async () => {
    const f = vi.fn();
    const e = ambiente();
    const a = criarAtualizador(f, 1_000, e.amb);
    expect(e.ouvintes()).toBe(2);
    a.parar();
    await vi.advanceTimersByTimeAsync(5_000);
    expect(f).not.toHaveBeenCalled();
    expect(e.ouvintes()).toBe(0);
  });
});

describe('carga', () => {
  it('caixa aberta: 20 + 6 + 2 = 28 chamadas/min por pessoa', () => {
    expect(chamadasPorMinuto([INTERVALO.conversaAberta, INTERVALO.listaConversas, INTERVALO.sino])).toBe(28);
  });
  it('com o aviso do banco conectado: 4 + 2 + 2 = 8 chamadas/min de reserva', () => {
    expect(chamadasPorMinuto([INTERVALO_COM_AVISO.conversaAberta, INTERVALO_COM_AVISO.listaConversas, INTERVALO_COM_AVISO.sino])).toBe(8);
  });
});

describe('reaproveitar', () => {
  const m = (id: string, status: string | null = 'enviada', em = '2026-10-07T10:00:00Z') => ({ id, status, em });

  it('nada mudou: mesma referência (React não re-renderiza)', () => {
    const antes = [m('a'), m('b')];
    expect(reaproveitar(antes, [m('a'), m('b')])).toBe(antes);
  });

  it('mudou o status de uma: lista nova, as outras mantêm a referência', () => {
    const antes = [m('a'), m('b')];
    const r = reaproveitar(antes, [m('a'), m('b', 'lida')]);
    expect(r).not.toBe(antes);
    expect(r[0]).toBe(antes[0]);
    expect(r[1]).toEqual(m('b', 'lida'));
  });

  it('mensagem nova entra sem duplicar as existentes', () => {
    const antes = [m('a'), m('b')];
    const r = reaproveitar(antes, [m('a'), m('b'), m('c')]);
    expect(r.map((x) => x.id)).toEqual(['a', 'b', 'c']);
    expect(r[1]).toBe(antes[1]);
  });

  it('id repetido na resposta: fica uma só, com a versão mais nova', () => {
    const r = reaproveitar(null, [m('a', null), m('b'), m('a', 'entregue')]);
    expect(r).toEqual([m('a', 'entregue'), m('b')]);
  });

  it('mídia pendente → ok troca a mensagem', () => {
    const antes = [{ id: 'x', em: '1', midia: { status: 'pendente' } }];
    const r = reaproveitar(antes, [{ id: 'x', em: '1', midia: { status: 'ok' } }]);
    expect(r[0].midia.status).toBe('ok');
  });

  it('conversas (chave contatoId): reordena mantendo as referências', () => {
    const antes = [{ contatoId: '1', n: 0 }, { contatoId: '2', n: 0 }];
    const r = reaproveitar(antes, [{ contatoId: '2', n: 0 }, { contatoId: '1', n: 0 }]);
    expect(r).not.toBe(antes);
    expect(r[0]).toBe(antes[1]);
    expect(r[1]).toBe(antes[0]);
  });

  it('objeto e valor simples', () => {
    const o = { a: 1 };
    expect(reaproveitar(o, { a: 1 })).toBe(o);
    expect(reaproveitar(o, { a: 2 })).toEqual({ a: 2 });
    expect(reaproveitar(null, 3)).toBe(3);
  });
});

describe('estaNoFim', () => {
  it('no fim ou perto dele', () => {
    expect(estaNoFim(900, 1500, 600)).toBe(true);
    expect(estaNoFim(850, 1500, 600)).toBe(true);
  });
  it('lendo o histórico mais acima', () => {
    expect(estaNoFim(200, 1500, 600)).toBe(false);
  });
});
