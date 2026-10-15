// Contrato da aba Lives contra as respostas REAIS das RPCs (copiadas de produção em 15/10/2026, ver
// respostas-rpc-lives-reais.ts), não contra um formato presumido. Os números esperados (pico 363, 125 e 342; chat do
// Studio 291, 102 e 242; comentários 3, 4 e 2) foram medidos no banco e no CSV do Studio.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({}) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

import { fimEmPctDoPico, marcosDaCurva, picoContraAnterior, somaOuNull, type Live } from '../domain/lives';
import { lerCsvStudio } from '../domain/lives-studio';
import { dataCurta, horaDe, posicaoTexto, quando } from '../ui/lives/formatos';
import { mapearDetalheLive, mapearLives, mapearPreviaImportacao } from './fonte-supabase';
import {
  MINUTOS_REAIS_06_10, MINUTOS_REAIS_08_10, MINUTOS_REAIS_13_10, minutosReais, RESPOSTA_LIVES_REAL,
} from './respostas-rpc-lives-reais';
import { lerZipStudio } from './zip-studio';

const { data: LIVES } = mapearLives(RESPOSTA_LIVES_REAL);
const live = (id: string) => LIVES.find((l) => l.videoId === id) as Live;

const REAIS = [
  { id: 'fpgmDwBKVcQ', minutos: MINUTOS_REAIS_06_10, zip: 'consultoria-06-10.zip', pico: 363, picoMin: 48, cheiaMin: 18, ultimo: 245, chat: 291, reacoes: 48, comentarios: 3, quando: 'ter 06/10 19:30' },
  { id: 'Hdsg23VbfHI', minutos: MINUTOS_REAIS_08_10, zip: 'primeiro-pilar-08-10.zip', pico: 125, picoMin: 59, cheiaMin: 50, ultimo: 41, chat: 102, reacoes: 2, comentarios: 4, quando: 'qui 08/10 19:30' },
  { id: 't0PLYUORt1E', minutos: MINUTOS_REAIS_13_10, zip: 'consultoria-13-10.zip', pico: 342, picoMin: 58, cheiaMin: 18, ultimo: 52, chat: 242, reacoes: 61, comentarios: 2, quando: 'ter 13/10 19:30' },
] as const;

describe('dados_black_lives real -> mapearLives', () => {
  it('as 9 lives entram, na ordem do banco, com a string exata do título e sem perder nenhuma', () => {
    expect(RESPOSTA_LIVES_REAL.lives).toHaveLength(9);
    expect(LIVES).toHaveLength(9);
    expect(LIVES.map((l) => l.videoId)).toEqual(RESPOSTA_LIVES_REAL.lives.map((l) => l.video_id));
    expect(LIVES.map((l) => l.titulo)).toEqual(RESPOSTA_LIVES_REAL.lives.map((l) => l.titulo));
    expect(live('S1FILUs1ti0').tipo).toBe('black');
    expect(LIVES.every((l) => l.miniatura !== null)).toBe(true);
  });

  for (const r of REAIS) {
    it(`${r.id}: pico ${r.pico} (min ${r.picoMin}), chat do Studio ${r.chat}, reações ${r.reacoes}, comentários ${r.comentarios}`, () => {
      const l = live(r.id);
      expect(l).toMatchObject({
        situacao: 'realizada', temStudio: true, pico: r.pico, picoSeg: r.picoMin * 60, salaCheiaSeg: r.cheiaMin * 60,
        ultimoEspectadores: r.ultimo, chatTotal: r.chat, reacoesTotal: r.reacoes, comentarios: r.comentarios,
      });
      expect(l.espectadoresAgora).toBeNull();
      expect(quando(l.dataPrevista)).toBe(r.quando);
    });
  }

  it('live futura: o que o banco não mediu continua null (nunca zero); views 0 e comentários 0 da API são medidos e ficam 0', () => {
    for (const id of ['iFH3cD_G3n8', 'KhqVjpL5Wvs', 'bN2XvcTwvWA', 'm6zoEBBw1bQ', 'S1FILUs1ti0']) {
      const l = live(id);
      expect(l).toMatchObject({ situacao: 'em_breve', temStudio: false, pico: null, picoSeg: null, salaCheiaSeg: null, ultimoEspectadores: null, chatTotal: null, reacoesTotal: null, duracaoSeg: null, inicio: null, fim: null });
      expect(l.views).toBe(0);
      expect(l.chatGuardado).toBe(0);
    }
  });

  it('data_prevista vem em UTC com +00:00 e a tela mostra o horário de Brasília (22:30Z = 19:30; 23:00Z = 20:00)', () => {
    expect(live('fpgmDwBKVcQ').dataPrevista).toBe('2026-10-06T22:30:00+00:00');
    expect(`${dataCurta(live('S1FILUs1ti0').dataPrevista)} ${horaDe(live('S1FILUs1ti0').dataPrevista)}`).toBe('03/11 20:00');
    expect(`${dataCurta(live('iFH3cD_G3n8').dataPrevista)} ${horaDe(live('iFH3cD_G3n8').dataPrevista)}`).toBe('20/10 20:00');
  });

  it('pico ÷ pico da anterior do mesmo tipo: 13/10 contra 06/10 = 342 ÷ 363', () => {
    const c = picoContraAnterior(LIVES, live('t0PLYUORt1E'));
    expect(c).toMatchObject({ num: 342, den: 363 });
    expect(c!.razao).toBeCloseTo(0.9421, 4);
    expect(c!.contra.videoId).toBe('fpgmDwBKVcQ');
  });

  it('fim em % do pico = último minuto ÷ pico (245 ÷ 363)', () => {
    expect(fimEmPctDoPico(live('fpgmDwBKVcQ'))).toBeCloseTo(245 / 363, 6);
    expect(fimEmPctDoPico(live('S1FILUs1ti0'))).toBeNull();
  });
});

describe('dados_black_live_detalhe real -> mapearDetalheLive', () => {
  for (const r of REAIS) {
    it(`${r.id}: a curva do detalhe bate com os agregados da lista`, () => {
      const { data } = mapearDetalheLive({ minutos: minutosReais(r.minutos), chat: [], comentarios: [], fotos: [] });
      const l = live(r.id);
      const m = marcosDaCurva(data.minutos);
      expect(m.pico).toMatchObject({ espectadores: r.pico, minuto: r.picoMin, seg: l.picoSeg });
      expect(m.salaCheia?.seg).toBe(l.salaCheiaSeg);
      expect(data.minutos.at(-1)?.espectadores).toBe(l.ultimoEspectadores);
      expect(somaOuNull(data.minutos.map((x) => x.chat))).toBe(l.chatTotal);
      expect(somaOuNull(data.minutos.map((x) => x.reacoes))).toBe(l.reacoesTotal);
      expect(data.minutos.every((x) => x.origem === 'studio' && x.espectadores !== null && x.chat !== null && x.reacoes !== null)).toBe(true);
    });

    it(`${r.id}: o CSV do Studio no repositório tem exatamente os mesmos minutos que o banco`, async () => {
      const b = readFileSync(join(__dirname, '__fixtures__', 'lives-studio', r.zip));
      const zip = await lerZipStudio(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) as ArrayBuffer);
      expect(zip.ok).toBe(true);
      if (!zip.ok) return;
      const leitura = lerCsvStudio(zip.lido.csv);
      expect(leitura.erros).toEqual([]);
      const doCsv = leitura.linhas.map((x) => [x.seg, x.espectadores, x.chat ?? 0, x.reacoes ?? 0]);
      expect(doCsv).toEqual(r.minutos.map((t) => [...t]));
    });
  }

  it('chat com seg negativo (mensagem de antes da live), comentários e fotos no formato real', () => {
    const { data } = mapearDetalheLive({
      minutos: [],
      chat: [
        { seg: -6177, publicado_em: '2026-10-06T20:49:48.286693+00:00', texto: 'No aguardo!!' },
        { seg: 12, publicado_em: '2026-10-06T22:32:57.000000+00:00', texto: 'Boa noite' },
      ],
      comentarios: [{ publicado_em: '2026-10-07T00:46:23+00:00', texto: 'Excelente', curtidas: 0, respostas: 0 }],
      fotos: [{ coletado_em: '2026-10-15T20:50:01.268077+00:00', views: 1749, likes: 105, comentarios: 3 }],
    });
    expect(data.chat.map((m) => m.seg)).toEqual([-6177, 12]);
    expect(data.comentarios[0]).toMatchObject({ curtidas: 0, respostas: 0 });
    expect(data.fotos[0]).toMatchObject({ views: 1749, likes: 105, comentarios: 3 });
  });

  it('posição de mensagem anterior ao início: "-1:42:57", nunca "-2:-43:-57"', () => {
    expect(posicaoTexto(-6177)).toBe('-1:42:57');
    expect(posicaoTexto(-1551)).toBe('-25:51');
    expect(posicaoTexto(0)).toBe('0:00');
    expect(posicaoTexto(2880)).toBe('48:00');
    expect(posicaoTexto(5700)).toBe('1:35:00');
  });
});

describe('dados_black_live_importar (contrato pelo corpo SQL; não chamada em produção)', () => {
  it('as linhas do CSV passam na validação da função: seg e espectadores inteiros, chat e reações inteiros ou ausentes, nunca null', () => {
    const csv = [
      'Posição na transmissão ao vivo (segundos),Espectadores simultâneos na transmissão,Mensagens do chat ao vivo,Reações',
      '0,12,3,0', '60,20,,5', '120,25,x,',
    ].join('\n');
    const { linhas, erros } = lerCsvStudio(csv);
    expect(erros).toEqual([]);
    const enviado = JSON.parse(JSON.stringify(linhas)) as Array<Record<string, unknown>>;
    for (const e of enviado) {
      expect(Number.isInteger(e.seg) && Number.isInteger(e.espectadores)).toBe(true);
      for (const k of ['chat', 'reacoes']) if (k in e) expect(Number.isInteger(e[k])).toBe(true);
      expect(Object.values(e).includes(null)).toBe(false);
    }
    expect(enviado[1]).toEqual({ seg: 60, espectadores: 20, reacoes: 5 });
  });

  it('prévia e resposta: linhas, pico, pico_seg, duracao_seg (= último seg + 60), existentes, alteradas e gravado', () => {
    expect(mapearPreviaImportacao({ linhas: 96, pico: 363, pico_seg: 2880, duracao_seg: 5760, existentes: 96, alteradas: 0, gravado: false }))
      .toEqual({ linhas: 96, pico: 363, picoSeg: 2880, duracaoSeg: 5760, existentes: 96, alteradas: 0, gravado: false });
    expect(MINUTOS_REAIS_06_10.at(-1)![0] + 60).toBe(5760);
  });
});
