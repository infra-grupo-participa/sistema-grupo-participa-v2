import { describe, expect, it } from 'vitest';
import { motivoErro, traduzirCampanha, type ListasCampanha } from './campanha';
import { validarCodigoPagina, validarProjeto } from './projetos';

// Listas do seed da 20261005m (area-de-trafego.md, "Listas (Victor, 05/10/2026)").
const LISTAS: ListasCampanha = {
  gestores: ['CF', 'RS', 'EF'],
  objetivos: ['LEADS', 'VENDAS', 'REMARKETING', 'LEMBRETE', 'DISTRIBUIÇÃO'],
  projetos: ['PB26', 'HT33', 'SEMSET26', 'BF26'],
};
const t = (nome: string, l: ListasCampanha = LISTAS) => traduzirCampanha(nome, l);

describe('nome de campanha: válidos', () => {
  it('5 campos (teste de página): a campanha real do Victor', () => {
    const r = t('RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1');
    expect(r).toEqual({
      padrao: true, gestor: 'RS', projeto: 'PB26', objetivo: 'LEADS', descricao: 'TESTE DE ESCRITÓRIOS',
      descricaoPartes: ['TESTE DE ESCRITÓRIOS'], pagina: 'ak1', campos: 5,
      erros: [], avisos: [], nomeCanonico: 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1',
    });
  });
  it('utm_campaign nome|id: o id da plataforma no fim é descartado (igual ao banco, 20261006e)', () => {
    const r = t('RS | PB26 | LEADS | TESTE | AK1|120211234');
    expect(r.pagina).toBe('ak1');
    expect(r.descricao).toBe('TESTE');
    expect(r.padrao).toBe(true);
  });
  it('4 campos: página nula', () => {
    const r = t('CF | HT33 | VENDAS | ABERTURA DE CARRINHO');
    expect(r.padrao).toBe(true);
    expect(r.pagina).toBeNull();
    expect(r.avisos).toEqual([]);
  });
  it('sub-variante de página (AK1-B) e geração (AK21)', () => {
    expect(t('RS | PB26 | LEADS | X | AK1-B').pagina).toBe('ak1-b');
    expect(t('RS | PB26 | LEADS | X | AK21').padrao).toBe(true);
  });
  it('minúsculas: continua no padrão, com aviso, e devolve a forma canônica', () => {
    const r = t('cf|ht33|vendas|aula ao vivo');
    expect(r.padrao).toBe(true);
    expect(r.avisos).toEqual(['minusculas', 'espacos_extras']);
    expect(r.nomeCanonico).toBe('CF | HT33 | VENDAS | AULA AO VIVO');
  });
  it('espaços extras: limpa e avisa', () => {
    const r = t('RS  |  PB26 |LEADS|   TESTE    DE   ESCRITÓRIOS  ');
    expect(r.padrao).toBe(true);
    expect(r.descricao).toBe('TESTE DE ESCRITÓRIOS');
    expect(r.avisos).toEqual(['espacos_extras']);
  });
  it('objetivo sem acento casa com o canônico (DISTRIBUICAO → DISTRIBUIÇÃO)', () => {
    const r = t('EF  |  BF26 | DISTRIBUICAO |  Oferta   final');
    expect(r.padrao).toBe(true);
    expect(r.objetivo).toBe('DISTRIBUIÇÃO');
    expect(r.avisos).toEqual(['sem_acento', 'minusculas', 'espacos_extras']);
    expect(r.nomeCanonico).toBe('EF | BF26 | DISTRIBUIÇÃO | OFERTA FINAL');
  });
  it('sem a lista de projetos, só confere o formato da sigla', () => {
    expect(t('RS | XY99 | LEADS | X', { gestores: LISTAS.gestores, objetivos: LISTAS.objetivos }).padrao).toBe(true);
  });
});

describe('nome de campanha: descrição de várias partes (revisão de 06/10/2026)', () => {
  it('o exemplo real da Black Friday do Caio: descrição de 5 partes, sem página; numa lista SEM ANTECIPAÇÃO, fora só pelo objetivo', () => {
    const r = t('CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY');
    expect(r).toMatchObject({
      gestor: 'CF', projeto: 'BF26', objetivo: 'ANTECIPAÇÃO', descricao: 'TEASER | META | PQ | ABO | THRUPLAY',
      descricaoPartes: ['TEASER', 'META', 'PQ', 'ABO', 'THRUPLAY'], pagina: null, campos: 8, padrao: false, erros: ['objetivo_desconhecido'],
    });
    expect(motivoErro(r.erros[0], r)).toBe('Objetivo ANTECIPAÇÃO não está na lista');
  });
  it('com ANTECIPAÇÃO na lista (decisão do Victor, 06/10/2026: semente da 20261006e), entra no padrão com ou sem acento', () => {
    const l = { ...LISTAS, objetivos: [...LISTAS.objetivos, 'ANTECIPAÇÃO'] };
    const r = t('CF | BF26 | ANTECIPACAO | TEASER | META | PQ | ABO | THRUPLAY', l);
    expect(r.padrao).toBe(true);
    expect(r.objetivo).toBe('ANTECIPAÇÃO');
    expect(r.avisos).toEqual(['sem_acento']);
    expect(r.nomeCanonico).toBe('CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY');
  });
  it('várias partes com página no fim', () => {
    const r = t('CF | BF26 | LEADS | TEASER | META | AK1');
    expect(r).toMatchObject({ padrao: true, descricao: 'TEASER | META', pagina: 'ak1', nomeCanonico: 'CF | BF26 | LEADS | TEASER | META | AK1' });
    expect(t('CF | BF26 | LEADS | TEASER | jt10').pagina).toBe('jt10');
  });
  it('último campo fora do formato de slug é descrição (antes era página inválida)', () => {
    const r = t('RS | PB26 | LEADS | TESTE | OBRIGADO');
    expect(r).toMatchObject({ padrao: true, pagina: null, descricao: 'TESTE | OBRIGADO' });
    expect(t('RS | PB26 | LEADS | TESTE | A1').descricao).toBe('TESTE | A1');
  });
  it('com 4 campos o quarto é a descrição, mesmo com cara de slug; slug no meio é descrição', () => {
    expect(t('RS | PB26 | LEADS | AK1')).toMatchObject({ padrao: true, pagina: null, descricao: 'AK1' });
    expect(t('RS | PB26 | LEADS | AK1 | TESTE')).toMatchObject({ pagina: null, descricao: 'AK1 | TESTE' });
  });
});

describe('nome de campanha: fora do padrão', () => {
  it('vazio', () => {
    expect(t('   ').erros).toEqual(['vazio']);
    expect(traduzirCampanha(null, LISTAS).erros).toEqual(['vazio']);
  });
  it('menos de 3 campos', () => {
    const r = t('RS | PB26');
    expect(r.erros).toEqual(['numero_de_campos']);
    expect(r.gestor).toBeNull();
    expect(motivoErro('numero_de_campos', r)).toBe('Menos de 3 campos (tem 2)');
  });
  it('só 3 campos: sem descrição (gestor, projeto e objetivo já lidos)', () => {
    const r = t('RS | PB26 | LEADS');
    expect(r.erros).toEqual(['descricao_vazia']);
    expect(r.projeto).toBe('PB26');
  });
  it('6 campos não é mais erro', () => {
    expect(t('RS | PB26 | LEADS | X | AK1 | Y')).toMatchObject({ padrao: true, descricao: 'X | AK1 | Y', pagina: null });
  });
  it('campo vazio dentro da descrição', () => {
    expect(t('RS | PB26 | LEADS | X |  | Y').erros).toEqual(['campo_vazio']);
    expect(t('RS | PB26 | LEADS | TESTE | ').erros).toEqual(['campo_vazio']);
  });
  it('sigla inválida', () => {
    for (const s of ['P26X', 'PB-26', 'PB', '26PB', 'P26']) {
      const r = t(`RS | ${s} | LEADS | TESTE`);
      expect(r.padrao, s).toBe(false);
      expect(r.erros, s).toEqual(['sigla_invalida']);
    }
  });
  it('sigla no formato, mas não cadastrada', () => {
    expect(t('RS | ZZ99 | LEADS | TESTE').erros).toEqual(['projeto_nao_cadastrado']);
  });
  it('objetivo fora da lista', () => {
    const r = t('RS | PB26 | TOPO | TESTE');
    expect(r.erros).toEqual(['objetivo_desconhecido']);
    expect(r.objetivo).toBe('TOPO');
  });
  it('gestor fora da lista, com o motivo exato', () => {
    const r = t('XX | PB26 | LEADS | TESTE');
    expect(r.erros).toEqual(['gestor_desconhecido']);
    expect(motivoErro('gestor_desconhecido', r)).toBe('Gestor XX não está na lista');
    expect(motivoErro('projeto_nao_cadastrado', t('RS | ZZ99 | LEADS | X'))).toBe('Projeto ZZ99 não cadastrado');
  });
  it('descrição vazia', () => {
    expect(t('RS | PB26 | LEADS |  ').erros).toEqual(['descricao_vazia']);
  });
  it('vários erros juntos', () => {
    expect(t('XX | P26X | TOPO | TESTE | A1').erros).toEqual(['gestor_desconhecido', 'sigla_invalida', 'objetivo_desconhecido']);
  });
});

describe('formulários', () => {
  it('validarProjeto', () => {
    expect(validarProjeto({ sigla: 'pb26', nome: 'Patrimônio Brasil 2026', linha: 'Patrimônio Brasil' })).toBeNull();
    expect(validarProjeto({ sigla: 'PB-26', nome: 'X X', linha: 'X X' })).toMatch(/Sigla inválida/);
    expect(validarProjeto({ sigla: 'PB26', nome: 'X X', linha: 'X X', etiqueta_clickup: 'Black Friday' })).toMatch(/Etiqueta/);
    expect(validarProjeto({ sigla: 'PB26', nome: 'X X', linha: 'X X', inicio: '2026-11-10', fim: '2026-11-01' })).toMatch(/fim/);
  });
  it('validarCodigoPagina', () => {
    for (const c of ['ak1', 'AK1', 'bl2', 'ak1-b', 'jt10', 'ak21', '']) expect(validarCodigoPagina(c), c).toBeNull();
    for (const c of ['a1', 'ak', 'ak1b', 'ak1-bb', 'abc1', 'obrigado']) expect(validarCodigoPagina(c), c).not.toBeNull();
  });
});
