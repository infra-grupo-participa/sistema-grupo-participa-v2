// A tela (HTML renderizado no servidor, sem navegador) com as respostas reais de produção: o que o líder lê tem que bater
// com o banco. Pico 363, 125 e 342; chat do Studio 291, 102 e 242; comentários 3, 4 e 2.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({}) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

import type { FonteDadosBlack } from '../../application/ports';
import { mapearLives } from '../../infrastructure/fonte-supabase';
import { RESPOSTA_LIVES_REAL } from '../../infrastructure/respostas-rpc-lives-reais';
import { CartoesRealizadas } from './CartoesRealizadas';
import { ChatLive, ComentariosLive } from './ChatLive';
import { DetalheLive } from './DetalheLive';

const { data: LIVES } = mapearLives(RESPOSTA_LIVES_REAL);
const texto = (html: string) => html.replace(/<[^>]+>/g, ' ').replace(/&#x27;/g, "'").replace(/\s+/g, ' ');

describe('tela da aba Lives com as respostas reais', () => {
  it('cartões das realizadas: pico, minuto do pico e chat do Studio de cada live', () => {
    const t = texto(renderToStaticMarkup(createElement(CartoesRealizadas, { lives: LIVES, onAbrir: () => {}, isMaster: false, onImportar: () => {} })));
    for (const [pico, min, chat] of [[363, 48, 291], [125, 59, 102], [342, 58, 242]]) {
      expect(t).toContain(`${pico} · min ${min}`);
      expect(t).toContain(`${chat} msg`);
    }
    expect(t).not.toContain('Sem o CSV do Studio');
  });

  it('detalhe de cada live: KPIs de pico, chat, reações e comentários', () => {
    const fonte = {} as FonteDadosBlack;
    for (const [id, pico, chat, reacoes, coment] of [['fpgmDwBKVcQ', 363, 291, 48, 3], ['Hdsg23VbfHI', 125, 102, 2, 4], ['t0PLYUORt1E', 342, 242, 61, 2]] as const) {
      const live = LIVES.find((l) => l.videoId === id)!;
      const t = texto(renderToStaticMarkup(createElement(DetalheLive, {
        live, lives: LIVES, fonte, chave: 'black-friday-2026-10', agoraMs: Date.parse('2026-10-15T21:30:00Z'), relogio: new Date('2026-10-15T21:30:00Z'),
        onVoltar: () => {}, isMaster: false, onImportar: () => {},
      })));
      expect(t).toMatch(new RegExp(`Pico ${pico} min \\d+`));
      expect(t).toContain(`Chat ${chat} msg`);
      expect(t).toContain(`Reações ${reacoes}`);
      expect(t).toContain(`${coment} na API`);
    }
  });

  it('chat e comentários: só o texto, sem nome de autor, e a busca não procura em autor (o campo nem existe)', () => {
    const chat = [{ seg: 10, publicadoEm: null, texto: 'Boa noite!' }, { seg: -90, publicadoEm: null, texto: 'No aguardo' }];
    const com = [{ publicadoEm: '2026-10-07T00:46:23+00:00', texto: 'Excelente', curtidas: 0, respostas: 0 }];
    const bruto = renderToStaticMarkup(createElement(ChatLive, { chat, minuto: null, onLimparMinuto: () => {}, guardado: 2 }));
    const c = texto(bruto);
    expect(c).toContain('Boa noite!');
    expect(c).toContain('No aguardo');
    expect(c).toContain('-1:30');
    expect(bruto).toContain('placeholder="Buscar no chat"');
    expect(bruto).not.toMatch(/autor/i);
    const k = texto(renderToStaticMarkup(createElement(ComentariosLive, { comentarios: com, total: 1 })));
    expect(k).toContain('Excelente');
    expect(k).toContain('06/10 21:46');
    expect(k).not.toMatch(/autor/i);
  });
});
