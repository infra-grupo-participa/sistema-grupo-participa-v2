import { describe, expect, it } from 'vitest';
import { textosDaSecao } from './busca';
import { SECOES } from './conteudo';
import { CENTRAL, PARTES, PRIMEIRO_DIA, TELAS, secoesDaParte } from './ajuda-conteudo';

const ROTAS = new Set(['/comercial', ...['funil', 'conversas', 'atividades', 'contatos', 'recuperacao', 'disparos', 'relatorios',
  'produtos', 'registro', 'playbook', 'social-selling', 'configuracoes'].map((r) => `/comercial/${r}`)]);
const ids = new Set(CENTRAL.map((s) => s.id));
const ancoras = new Set(PARTES.map((p) => p.ancora));

describe('central de ajuda: estrutura', () => {
  it('tem as seis partes, ids únicos e nenhuma âncora repetida entre parte e seção', () => {
    expect(PARTES.map((p) => p.key)).toEqual(['comece', 'sistema', 'modulos', 'playbook', 'faq', 'glossario']);
    expect(ids.size).toBe(CENTRAL.length);
    for (const a of ancoras) expect(ids.has(a)).toBe(false);
    for (const p of PARTES) expect(secoesDaParte(p.key).length, p.key).toBeGreaterThan(0);
  });

  it('não perde nada do playbook: toda seção dele está na central, com os mesmos blocos', () => {
    for (const s of SECOES) {
      const c = CENTRAL.find((x) => x.id === s.id);
      expect(c, s.id).toBeDefined();
      expect(c!.blocos).toBe(s.blocos);
    }
    expect(secoesDaParte('playbook').map((s) => s.id)).toContain('inegociaveis');
    expect(CENTRAL.find((s) => s.id === 'glossario')!.parte).toBe('glossario');
  });

  it('tem uma seção por tela do Comercial, com âncora #modulo-*', () => {
    const modulos = secoesDaParte('modulos').map((s) => s.id);
    for (const id of ['inicio', 'funil', 'ficha-negocio', 'conversas', 'atividades', 'contatos', 'recuperacao', 'disparos',
      'relatorios', 'dashboards', 'equipe', 'produtos', 'registro', 'configuracoes', 'notificacoes', 'social-selling']) {
      expect(modulos).toContain(`modulo-${id}`);
    }
  });

  it('cada módulo pronto tem passo a passo, dicas, erros comuns e link para a tela', () => {
    for (const s of secoesDaParte('modulos').filter((x) => !x.emBreve)) {
      const tipos = new Set(s.blocos.map((b) => b.tipo));
      expect(tipos.has('passos'), s.id).toBe(true);
      expect(tipos.has('dicas'), s.id).toBe(true);
      expect(tipos.has('cuidados'), s.id).toBe(true);
      expect(s.ferramentas?.length, s.id).toBeGreaterThan(0);
    }
  });

  it('o que é futuro está marcado como em breve (WhatsApp, Hotmart, Clint, assistente de IA, social selling)', () => {
    const emBreve = CENTRAL.flatMap((s) => s.blocos).filter((b) => b.tipo === 'em_breve').map((b) => b.tipo === 'em_breve' ? `${b.titulo} ${b.texto}` : '').join(' ');
    for (const t of ['WhatsApp', 'Hotmart', 'Clint', 'IA', 'Instagram']) expect(emBreve).toContain(t);
    expect(CENTRAL.find((s) => s.id === 'modulo-social-selling')!.emBreve).toBe(true);
  });

  it('todo link aponta para uma tela que existe ou para uma seção/parte da central', () => {
    const hrefs = [
      ...Object.values(TELAS).map((t) => t.href),
      ...CENTRAL.flatMap((s) => s.ferramentas ?? []).map((f) => f.href),
      ...CENTRAL.flatMap((s) => s.blocos).flatMap((b) => (b.tipo === 'atalhos' ? b.itens.map((a) => a.href) : b.tipo === 'pergunta' && b.link ? [b.link.href] : [])),
    ];
    for (const h of hrefs) {
      if (h.startsWith('#')) expect(ids.has(h.slice(1)) || ancoras.has(h.slice(1)), h).toBe(true);
      else expect(ROTAS.has(h.split('#')[0]), h).toBe(true);
    }
    for (const g of PRIMEIRO_DIA) expect(ids.has(g.id)).toBe(true);
  });

  it('a parte de perguntas só tem perguntas, e cada uma tem resposta', () => {
    for (const s of secoesDaParte('faq')) {
      expect(s.blocos.every((b) => b.tipo === 'pergunta' && b.resposta.length > 10), s.id).toBe(true);
    }
  });

  it('a ajuda do sistema não usa jargão técnico', () => {
    const texto = CENTRAL.filter((s) => s.parte !== 'playbook' && s.id !== 'glossario').flatMap(textosDaSecao).join(' ');
    expect(texto).not.toMatch(/\b(RPC|RLS|Supabase|backend|endpoint|webhook|SQL|JSON)\b/i);
  });
});
