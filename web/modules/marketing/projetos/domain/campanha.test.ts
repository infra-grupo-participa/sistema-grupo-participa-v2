import { describe, expect, it } from 'vitest';
import { traduzirCampanha, type ListasCampanha } from './campanha';
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
      padrao: true, gestor: 'RS', projeto: 'PB26', objetivo: 'LEADS', descricao: 'TESTE DE ESCRITÓRIOS', pagina: 'ak1',
      erros: [], avisos: [], nomeCanonico: 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1',
    });
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

describe('nome de campanha: fora do padrão', () => {
  it('vazio', () => {
    expect(t('   ').erros).toEqual(['vazio']);
    expect(traduzirCampanha(null, LISTAS).erros).toEqual(['vazio']);
  });
  it('número de campos errado (3 e 6)', () => {
    expect(t('RS | PB26 | LEADS').erros).toEqual(['numero_de_campos']);
    expect(t('RS | PB26 | LEADS | X | AK1 | Y').erros).toEqual(['numero_de_campos']);
    expect(t('RS | PB26 | LEADS').gestor).toBeNull();
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
  it('gestor fora da lista', () => {
    expect(t('XX | PB26 | LEADS | TESTE').erros).toEqual(['gestor_desconhecido']);
  });
  it('descrição vazia', () => {
    expect(t('RS | PB26 | LEADS |  ').erros).toEqual(['descricao_vazia']);
  });
  it('página fora do padrão da casa', () => {
    expect(t('RS | PB26 | LEADS | TESTE | A1').erros).toEqual(['pagina_invalida']);
    expect(t('RS | PB26 | LEADS | TESTE | OBRIGADO').erros).toEqual(['pagina_invalida']);
    expect(t('RS | PB26 | LEADS | TESTE | ').erros).toEqual(['pagina_invalida']);
  });
  it('vários erros juntos', () => {
    expect(t('XX | P26X | TOPO | TESTE | A1').erros).toEqual(['gestor_desconhecido', 'sigla_invalida', 'objetivo_desconhecido', 'pagina_invalida']);
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
