import { describe, expect, it } from 'vitest';
import {
  contagemRegressiva, curvaComparativa, duracaoTexto, filtrarChat, filtrarComentarios, fimEmPctDoPico, idDoYoutube, marcosDaCurva,
  minutoDe, picoContraAnterior, pontosDeEvolucao, posicaoContraAnterior, somaOuNull, ultimaRealizadaDoTipo, type Live, type MinutoLive,
} from './lives';

const live = (videoId: string, tipo: Live['tipo'], dataPrevista: string, extra: Partial<Live> = {}): Live => ({
  videoId, tipo, dataPrevista, titulo: `Live ${videoId}`, miniatura: null, situacao: 'realizada', agendadaEm: null, inicio: null, fim: null,
  duracaoSeg: null, views: null, likes: null, comentarios: null, coletadoEm: null, espectadoresAgora: null, temStudio: true,
  pico: null, picoSeg: null, salaCheiaSeg: null, ultimoEspectadores: null, chatTotal: null, reacoesTotal: null, chatGuardado: null, ...extra,
});
const minutos = (v: (number | null)[]): MinutoLive[] => v.map((e, i) => ({ seg: i * 60, espectadores: e, chat: null, reacoes: null, origem: 'studio' }));

describe('comparação com a anterior do mesmo tipo', () => {
  const lives = [
    live('AAAAAAAAAAA', 'consultoria', '2026-10-06T22:30:00Z', { pico: 363 }),
    live('BBBBBBBBBBB', 'produto', '2026-10-08T22:30:00Z', { pico: 125 }),
    live('CCCCCCCCCCC', 'consultoria', '2026-10-13T22:30:00Z', { pico: 342 }),
    live('DDDDDDDDDDD', 'consultoria', '2026-10-20T23:00:00Z', { situacao: 'em_breve' }),
  ];
  it('13/10 contra 06/10 = 342 ÷ 363 (94,2%)', () => {
    const r = picoContraAnterior(lives, lives[2]);
    expect(r?.num).toBe(342); expect(r?.den).toBe(363);
    expect(r!.razao).toBeCloseTo(0.9421, 4);
    expect(r?.contra.videoId).toBe('AAAAAAAAAAA');
  });
  it('a primeira do tipo e a que não tem pico não têm comparação (null, não zero)', () => {
    expect(picoContraAnterior(lives, lives[0])).toBeNull();
    expect(picoContraAnterior(lives, lives[1])).toBeNull();
    expect(picoContraAnterior(lives, lives[3])).toBeNull();
  });
  it('a última realizada do mesmo tipo, para a curva ao vivo', () => {
    expect(ultimaRealizadaDoTipo(lives, lives[3])?.videoId).toBe('CCCCCCCCCCC');
    expect(ultimaRealizadaDoTipo(lives, lives[1])).toBeNull();
  });
  it('série de evolução na ordem do calendário', () => {
    const p = pontosDeEvolucao([...lives].reverse());
    expect(p.map((x) => x.videoId)).toEqual(['AAAAAAAAAAA', 'BBBBBBBBBBB', 'CCCCCCCCCCC', 'DDDDDDDDDDD']);
    expect(p[2].contraAnterior).toBeCloseTo(0.9421, 4);
    expect(p[3].pico).toBeNull();
  });
});

describe('marcos da curva', () => {
  it('pico, sala cheia (primeiro minuto >= 90% do pico) e as 2 maiores quedas sem sobreposição', () => {
    const m = marcosDaCurva(minutos([10, 50, 95, 100, 98, 60, 55, 54, 20, 18]));
    expect(m.pico).toMatchObject({ minuto: 3, espectadores: 100 });
    expect(m.salaCheia).toMatchObject({ minuto: 2, espectadores: 95 });
    expect(m.quedas).toHaveLength(2);
    expect(m.quedas[0]).toMatchObject({ deMinuto: 4, ateMinuto: 6, de: 98, ate: 55, perda: 43 });
    expect(m.quedas[1]).toMatchObject({ deMinuto: 7, ateMinuto: 9, de: 54, ate: 18 });
  });
  it('minuto sem dado não vira zero nem entra na conta', () => {
    const m = marcosDaCurva(minutos([null, 10, null, 30]));
    expect(m.pico).toMatchObject({ minuto: 3, espectadores: 30 });
    expect(m.quedas).toEqual([]);
  });
  it('sem minutos, sem marcos', () => {
    expect(marcosDaCurva([])).toEqual({ pico: null, salaCheia: null, quedas: [] });
  });
});

describe('curva comparativa', () => {
  it('alinha pelo minuto e mostra onde a atual está contra a anterior', () => {
    const p = curvaComparativa(minutos([5, 40, 60]), minutos([4, 30, 70, 90, 80]));
    expect(p).toHaveLength(5);
    expect(p[3]).toEqual({ minuto: 3, atual: null, anterior: 90 });
    expect(posicaoContraAnterior(p)).toEqual({ minuto: 2, atual: 60, anterior: 70, diferenca: -10 });
  });
});

describe('números e textos', () => {
  it('fim em % do pico: null se falta uma ponta', () => {
    expect(fimEmPctDoPico({ ultimoEspectadores: 245, pico: 363 })).toBeCloseTo(0.675, 3);
    expect(fimEmPctDoPico({ ultimoEspectadores: null, pico: 363 })).toBeNull();
    expect(fimEmPctDoPico({ ultimoEspectadores: 10, pico: 0 })).toBeNull();
  });
  it('soma ignora null e só devolve null se tudo for null', () => {
    expect(somaOuNull([null, 2, null, 3])).toBe(5);
    expect(somaOuNull([null, null])).toBeNull();
    expect(somaOuNull([0, null])).toBe(0);
  });
  it('duração e minuto', () => {
    expect(duracaoTexto(5687)).toBe('1h34m47s');
    expect(duracaoTexto(null)).toBe('Sem dado');
    expect(minutoDe(2879)).toBe(47);
  });
  it('contagem regressiva até a Black', () => {
    const alvo = '2026-11-03T20:00:00-03:00';
    const antes = Date.parse('2026-10-15T20:00:00-03:00');
    expect(contagemRegressiva(antes, alvo)).toMatchObject({ dias: 19, horas: 0, minutos: 0, segundos: 0, passou: false });
    expect(contagemRegressiva(Date.parse(alvo) + 61_000, alvo)).toMatchObject({ minutos: 1, segundos: 1, passou: true });
    expect(contagemRegressiva(0, 'lixo')).toBeNull();
  });
  it('id do YouTube só de link do YouTube ou id puro', () => {
    expect(idDoYoutube('fpgmDwBKVcQ')).toBe('fpgmDwBKVcQ');
    expect(idDoYoutube('https://www.youtube.com/watch?v=fpgmDwBKVcQ&t=3s')).toBe('fpgmDwBKVcQ');
    expect(idDoYoutube('https://youtu.be/fpgmDwBKVcQ?si=x')).toBe('fpgmDwBKVcQ');
    expect(idDoYoutube('https://www.youtube.com/live/fpgmDwBKVcQ')).toBe('fpgmDwBKVcQ');
    expect(idDoYoutube('https://exemplo.com/watch?v=fpgmDwBKVcQ')).toBeNull();
    expect(idDoYoutube('curto')).toBeNull();
  });
});

describe('chat e comentários', () => {
  const chat = [
    { seg: 10, publicadoEm: null, texto: 'Boa noite!' },
    { seg: 70, publicadoEm: null, texto: 'Qual é o próximo pilar?' },
    { seg: null, publicadoEm: null, texto: 'sem posição' },
  ];
  it('filtra pelo minuto da curva e pelo texto, sem diferenciar acento', () => {
    expect(filtrarChat(chat, 1, '')).toHaveLength(1);
    expect(filtrarChat(chat, null, 'PROXIMO')).toHaveLength(1);
    expect(filtrarChat(chat, 0, 'proximo')).toHaveLength(0);
    expect(filtrarChat(chat, null, '')).toHaveLength(3);
  });
  it('comentários pelo texto', () => {
    const c = [{ publicadoEm: null, texto: 'Ótima aula', curtidas: null, respostas: null }];
    expect(filtrarComentarios(c, 'otima')).toHaveLength(1);
    expect(filtrarComentarios(c, 'xyz')).toHaveLength(0);
  });
});
