import { describe, expect, it } from 'vitest';
import { normalizarValorCampo, sugerirCampos } from './campos-negocio';

describe('normalizarValorCampo: fala natural → chave do banco', () => {
  it.each([
    ['perfil_profissional', 'é contadora', 'contador'],
    ['perfil_profissional', 'Contador', 'contador'],
    ['perfil_profissional', 'ele é advogado', 'advogado'],
    ['perfil_profissional', 'advogada tributarista', 'advogado'],
    ['perfil_profissional', 'tem OAB', 'advogado'],
    ['perfil_profissional', 'outro', 'outro'],
    ['atua_com_holding', 'começando', 'comecando'],
    ['atua_com_holding', 'está começando', 'comecando'],
    ['atua_com_holding', 'sim, já faz', 'sim'],
    ['atua_com_holding', 'já atua', 'sim'],
    ['atua_com_holding', 'Não', 'nao'],
    ['atua_com_holding', 'ainda não', 'nao'],
    ['produto_interesse', 'Holding Total', 'ht'],
    ['produto_interesse', 'HT', 'ht'],
    ['produto_interesse', 'Clínica Miami', 'clinica_miami'],
    ['produto_interesse', 'clínica internacional diamante', 'clinica_miami'],
    ['produto_interesse', 'Holding Masters', 'hm'],
    ['produto_interesse', 'Sessão de Viabilidade', 'sv'],
    ['produto_interesse', 'Acelera Holding', 'acelera'],
    ['forma_pagamento', 'pix', 'pix'],
    ['forma_pagamento', 'no cartão de crédito', 'cartao'],
    ['forma_pagamento', 'Boleto', 'boleto'],
    ['objecao_principal', 'achou caro', 'preco'],
    ['objecao_principal', 'vai pensar', 'pensar'],
    ['objecao_principal', 'falar com a esposa', 'socio_conjuge'],
    ['objecao_principal', 'sócio/cônjuge', 'socio_conjuge'],
    ['objecao_principal', 'não tem cliente', 'sem_cliente'],
    ['objecao_principal', 'ja_sei', 'ja_sei'],
  ])('%s: "%s" → %s', (campo, entrada, esperado) => {
    expect(normalizarValorCampo(campo, entrada)).toBe(esperado);
  });
  it('vazio ou null limpa; texto livre fica como veio; desconhecido vira slug (o banco recusa e lista as opções)', () => {
    expect(normalizarValorCampo('perfil_profissional', '')).toBe('');
    expect(normalizarValorCampo('perfil_profissional', '   ')).toBe('');
    expect(normalizarValorCampo('perfil_profissional', null)).toBe('');
    expect(normalizarValorCampo('origem', '  Indicação do João ')).toBe('Indicação do João');
    expect(normalizarValorCampo('produto_interesse', 'Curso Novo X')).toBe('curso_novo_x');
    expect(normalizarValorCampo('perfil_profissional', 'médico')).toBe('medico');
  });
});

describe('sugerirCampos: heurística determinística sobre a conversa', () => {
  const em = (h: number) => `2026-10-08T${String(h).padStart(2, '0')}:00:00Z`;
  it('só mensagem do cliente e nota; a fala da equipe (pitch) não conta', () => {
    const r = sugerirCampos([
      { fonte: 'mensagem', de: 'equipe', texto: 'O Holding Total é para advogados e contadores. Pode pagar no pix.', em: em(9) },
      { fonte: 'mensagem', de: 'cliente', texto: 'Oi! Sou advogada, OAB/SP, e já faço holding para alguns clientes.', em: em(10) },
    ]);
    expect(r.map((x) => `${x.campo}=${x.valor}`)).toEqual(['perfil_profissional=advogado', 'atua_com_holding=sim']);
    expect(r[0].trecho).toContain('Sou advogada');
    expect(r[0].fonte).toBe('mensagem');
  });
  it('contador por CRC, começando, produto e objeção; trecho preserva acento do original', () => {
    const r = sugerirCampos([
      { fonte: 'mensagem', de: 'cliente', texto: 'Tenho CRC ativo. Estou começando com holding e quero a Clínica Miami.', em: em(10) },
      { fonte: 'nota', texto: 'Disse que vai falar com o sócio antes de fechar.', em: em(11) },
    ]);
    expect(r.map((x) => `${x.campo}=${x.valor}`)).toEqual([
      'perfil_profissional=contador', 'atua_com_holding=comecando', 'produto_interesse=clinica_miami', 'objecao_principal=socio_conjuge',
    ]);
    expect(r.find((x) => x.campo === 'atua_com_holding')!.trecho).toContain('Estou começando com holding');
    expect(r.find((x) => x.campo === 'objecao_principal')!.fonte).toBe('nota');
  });
  it('valores conflitantes voltam todos (o Claude pergunta); a evidência mais recente fica', () => {
    const r = sugerirCampos([
      { fonte: 'mensagem', de: 'cliente', texto: 'nunca fiz holding', em: em(8) },
      { fonte: 'mensagem', de: 'cliente', texto: 'na verdade estou começando agora', em: em(12) },
      { fonte: 'mensagem', de: 'cliente', texto: 'estou começando', em: em(9) },
    ]);
    expect(r.map((x) => x.valor).sort()).toEqual(['comecando', 'nao']);
    expect(r.find((x) => x.valor === 'comecando')!.em).toBe(em(12));
  });
  it('nada a sugerir: lista vazia; texto vazio/nulo é ignorado', () => {
    expect(sugerirCampos([{ fonte: 'mensagem', de: 'cliente', texto: 'Bom dia, tudo bem?' }, { fonte: 'nota', texto: null }])).toEqual([]);
  });
});
