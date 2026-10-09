import { describe, expect, it } from 'vitest';
import { CENTRAL } from './ajuda-conteudo';
import { SECOES } from './conteudo';
import {
  LIMITE_PAGINA, URI_PLAYBOOK, blocoParaMarkdown, buscarPlaybook, indicePlaybook, lerRecursoPlaybook, lerSecao, markdownSecao,
  paginar, recursosPlaybook, slug, subsecoes,
} from './mcp-playbook';

describe('playbook no MCP: índice', () => {
  it('lista toda a central (playbook inteiro incluído), com resumo de 1 linha e subseções com id único', () => {
    const ind = indicePlaybook();
    expect(ind.map((s) => s.id)).toEqual(CENTRAL.map((s) => s.id));
    for (const s of SECOES) expect(ind.some((x) => x.id === s.id), s.id).toBe(true);
    for (const s of ind) {
      expect(s.resumo).not.toMatch(/\n|\*\*/);
      for (const sub of s.subsecoes) expect(sub.id.startsWith(`${s.id}/`)).toBe(true);
    }
    const subIds = ind.flatMap((s) => s.subsecoes.map((x) => x.id));
    expect(new Set(subIds).size).toBe(subIds.length);
  });
  it('filtra por parte', () => {
    const pb = indicePlaybook('playbook');
    expect(pb.length).toBeGreaterThan(10);
    expect(pb.every((s) => s.parte === 'Playbook de vendas')).toBe(true);
    expect(pb.map((s) => s.id)).toContain('inegociaveis');
  });
  it('slug sem acento e sem símbolo', () => {
    expect(slug('Escada A · serviço do escritório')).toBe('escada-a-servico-do-escritorio');
    expect(slug('***')).toBe('trecho');
  });
});

describe('playbook no MCP: leitura', () => {
  it('seção em markdown: título, id para citar, scripts e tabelas', () => {
    const r = lerSecao('conversa');
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.markdown.startsWith('# ')).toBe(true);
    expect(r.markdown).toContain('`conversa`');
    expect(r.markdown).toMatch(/\| --- \|/);
    expect(r.markdown).toMatch(/Está caro/);
    expect(r).toMatchObject({ pagina: 1, id: 'conversa' });
  });
  it('subseção traz só o trecho dela', () => {
    const secao = CENTRAL.find((s) => s.id === 'o-que-vende')!;
    const [primeira, segunda] = subsecoes(secao);
    const r = lerSecao(primeira.id);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.titulo).toBe(`${secao.titulo} › ${primeira.titulo}`);
    expect(r.markdown).not.toContain(`### ${segunda.titulo}`);
  });
  it('id inexistente e página fora do total viram erro com orientação', () => {
    expect(lerSecao('nao-existe')).toMatchObject({ ok: false, msg: expect.stringContaining('comercial_playbook_indice') });
    expect(lerSecao('conversa/nao-existe').ok).toBe(false);
    expect(lerSecao('conversa', 99)).toMatchObject({ ok: false });
  });
  it('seção grande pagina sem passar do limite e sem perder texto', () => {
    const maior = [...CENTRAL].sort((a, b) => markdownSecao(b.id)!.markdown.length - markdownSecao(a.id)!.markdown.length)[0];
    const inteiro = markdownSecao(maior.id)!.markdown;
    const limite = 2000;
    const p1 = lerSecao(maior.id, 1, limite);
    expect(p1.ok).toBe(true);
    if (!p1.ok) return;
    expect(p1.paginas).toBeGreaterThan(1);
    expect(p1.proximaPagina).toBe(2);
    const paginas = Array.from({ length: p1.paginas }, (_, i) => lerSecao(maior.id, i + 1, limite));
    for (const p of paginas) {
      expect(p.ok).toBe(true);
      if (p.ok) expect(p.markdown.length).toBeLessThanOrEqual(limite);
    }
    expect(paginas.map((p) => (p.ok ? p.markdown : '')).join('\n\n')).toBe(inteiro);
    const ultima = paginas[paginas.length - 1];
    expect(ultima.ok && ultima.proximaPagina).toBeNull();
  });
  it('bloco maior que o limite é fatiado; nenhuma seção real passa de 4 páginas no limite padrão', () => {
    const pags = paginar('# x', [{ tipo: 'paragrafo', texto: 'a'.repeat(250) }], 100);
    expect(pags.every((p) => p.length <= 100)).toBe(true);
    for (const s of CENTRAL) {
      const r = lerSecao(s.id);
      expect(r.ok && r.paginas, s.id).toBeLessThanOrEqual(4);
    }
    expect(LIMITE_PAGINA).toBe(12_000);
  });
  it('markdown dos blocos: alerta diz que não vale, em breve diz que não existe, pipe escapado na tabela', () => {
    expect(blocoParaMarkdown({ tipo: 'alerta', status: 'a_definir', texto: 'x', quem: 'Arthur' })).toBe('> **A definir (quem decide: Arthur):** x');
    expect(blocoParaMarkdown({ tipo: 'em_breve', titulo: 'VoIP', texto: 'y' })).toContain('ainda não existe');
    expect(blocoParaMarkdown({ tipo: 'tabela', colunas: ['a|b'], linhas: [['c']] })).toContain('a\\|b');
    expect(blocoParaMarkdown({ tipo: 'atalhos', itens: [{ rotulo: 'Funil', href: '/comercial/funil', texto: 't', icone: 'x' }] }))
      .toContain('https://grupoparticipa.app.br/comercial/funil');
  });
});

describe('playbook no MCP: busca (a mesma da tela)', () => {
  it('"objeção caro" acha o roteiro de objeções, com id e trecho', () => {
    const r = buscarPlaybook('objeção caro');
    expect(r.length).toBeGreaterThan(0);
    expect(r[0].id).toBe('conversa');
    expect(r[0].subsecao?.id).toBe('conversa/objecoes');
    expect(r[0].trecho).toBeTruthy();
  });
  it('garantia, template e Miami acham alguma seção; subseção aponta para um id que abre', () => {
    for (const termo of ['garantia', 'template', 'Miami']) {
      const r = buscarPlaybook(termo);
      expect(r.length, termo).toBeGreaterThan(0);
      for (const x of r) if (x.subsecao) expect(lerSecao(x.subsecao.id).ok, x.subsecao.id).toBe(true);
    }
  });
  it('respeita o limite e devolve vazio para termo curto ou inexistente', () => {
    expect(buscarPlaybook('template', 2)).toHaveLength(2);
    expect(buscarPlaybook('x')).toEqual([]);
    expect(buscarPlaybook('zzqqxx')).toEqual([]);
  });
});

describe('playbook no MCP: resources', () => {
  it('um resource por seção, markdown, URI playbook://comercial/<id>', () => {
    const rs = recursosPlaybook();
    expect(rs).toHaveLength(CENTRAL.length);
    expect(rs[0]).toMatchObject({ uri: `${URI_PLAYBOOK}${CENTRAL[0].id}`, mimeType: 'text/markdown' });
  });
  it('lê seção e subseção pelo URI; recusa o que não é do playbook', () => {
    expect(lerRecursoPlaybook(`${URI_PLAYBOOK}conversa`)?.text).toContain('# ');
    const sub = subsecoes(CENTRAL.find((s) => s.id === 'o-que-vende')!)[0];
    expect(lerRecursoPlaybook(`${URI_PLAYBOOK}${sub.id}`)?.text).toContain(sub.titulo);
    expect(lerRecursoPlaybook('playbook://comercial/nao-existe')).toBeNull();
    expect(lerRecursoPlaybook('file:///etc/passwd')).toBeNull();
    expect(lerRecursoPlaybook(`${URI_PLAYBOOK}%E0%A4%A`)).toBeNull();
    expect(lerRecursoPlaybook(42)).toBeNull();
  });
});
