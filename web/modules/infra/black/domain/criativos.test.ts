import { describe, expect, it } from 'vitest';
import { baseFicticia } from '../infrastructure/fixtures/gerador';
import { CONFIG_BLACK } from '../infrastructure/fixtures/catalogo';
import { conversaoPagina, ctr, agregar, indexar, ingressoGrupoGeral, mqlDoRecorte } from './metricas';
import { anunciosDoCriativo, funilCriativo, idDoCriativo, ORDENS_GALERIA, ordenar, painel, resumir, serieDiariaAnuncio, valorOrdem } from './criativos';
import { recorteDaTela, TETO_RECORTE_ANUNCIO } from './grupo';
import { grupoDemo } from '../infrastructure/fixtures/fonte-fixtures';
import type { LinhaPerfil } from './tipos';

const b = baseFicticia();
const idx = indexar(b);
const regua = CONFIG_BLACK.reguaCpl;
const nomePagina = (id: string) => id;

describe('criativo = anúncios de mesmo nome', () => {
  // Os fixtures dão um nome por conjunto. No Meta o mesmo criativo vira um anúncio por conjunto: aqui três anúncios de
  // conjuntos diferentes da campanha de iscas passam a ter o mesmo nome, como na planilha real (74 anúncios, 18 nomes).
  const NOME = 'FICTÍCIO CRIATIVO COMPARTILHADO';
  const doisConj = b.conjuntos.filter((c) => c.campanhaId === 'cp-iscas').slice(0, 3);
  const trio = doisConj.map((c) => b.anuncios.find((a) => a.conjuntoId === c.id)!.id).sort();
  const ba = { ...b, anuncios: b.anuncios.map((a) => (trio.includes(a.id) ? { ...a, nome: NOME } : a)) };
  const ix = indexar(ba);
  const itens = () => painel('anuncio', {}, ba.dias, ba.linhas, ix, regua, nomePagina);

  it('preparo: três anúncios, em conjuntos diferentes, com o mesmo nome', () => {
    expect(trio).toHaveLength(3);
    expect(new Set(trio.map((id) => ix.anuncio.get(id)!.conjuntoId)).size).toBe(3);
  });
  it('a galeria tem um cartão por nome, com o nome exato, e esses três viram um só', () => {
    const lista = itens();
    expect(lista.length).toBe(new Set(lista.map((i) => i.nome)).size);
    expect(lista.length).toBe(ba.anuncios.length - 2);
    const it = lista.find((i) => i.nome === NOME)!;
    expect([...it.anuncios].sort()).toEqual(trio);
  });
  it('o cartão soma os conjuntos: gasto do criativo = soma do gasto dos três anúncios', () => {
    const it = itens().find((i) => i.nome === NOME)!;
    const soma = ba.dias.filter((d) => trio.includes(d.anuncioId)).reduce((s, d) => s + d.gasto, 0);
    expect(soma).toBeGreaterThan(0);
    expect(it.resumo.gasto).toBeCloseTo(soma, 6);
  });
  it('soma de todos os cartões = gasto total (nada some nem conta duas vezes)', () => {
    expect(itens().reduce((s, i) => s + i.resumo.gasto, 0)).toBeCloseTo(ba.dias.reduce((s, d) => s + d.gasto, 0), 4);
  });
  it('o id do cartão é o mesmo para qualquer anúncio do grupo (o menor id); id desconhecido volta ele mesmo', () => {
    expect(idDoCriativo(ix, trio[2])).toBe(trio[0]);
    expect(idDoCriativo(ix, trio[1])).toBe(trio[0]);
    expect([...anunciosDoCriativo(ix, trio[1])].sort()).toEqual(trio);
    expect(anunciosDoCriativo(ix, 'nao-existe')).toEqual(['nao-existe']);
  });
  it('nome diferente não agrupa, mesmo parecido (nome exato)', () => {
    const outro = ba.anuncios.find((a) => !trio.includes(a.id))!;
    const bb = { ...ba, anuncios: ba.anuncios.map((a) => (a.id === outro.id ? { ...a, nome: NOME + ' ' } : a)) };
    expect(anunciosDoCriativo(indexar(bb), outro.id)).toEqual([outro.id]);
  });
  it('escolher o criativo filtra os conjuntos por todos os anúncios dele, não só por um', () => {
    const conj = painel('conjunto', { anuncio: trio[2] }, ba.dias, ba.linhas, ix, regua, nomePagina);
    expect(new Set(conj.map((c) => c.id))).toEqual(new Set(trio.map((id) => ix.anuncio.get(id)!.conjuntoId)));
  });
  it('criativo + conjunto: sobra o anúncio daquele conjunto', () => {
    const cj = ix.anuncio.get(trio[1])!.conjuntoId;
    const lista = painel('anuncio', { anuncio: trio[0], conjunto: cj }, ba.dias, ba.linhas, ix, regua, nomePagina);
    // o conjunto tem outro anúncio além do compartilhado; o compartilhado traz só o anúncio daquele conjunto
    expect(lista.map((i) => i.anuncios.length)).toEqual(lista.map(() => 1));
    expect(lista.find((i) => i.nome === NOME)!.anuncios).toEqual([trio[1]]);
    expect(lista.every((i) => i.anuncios.every((id) => ix.anuncio.get(id)!.conjuntoId === cj))).toBe(true);
  });
  it('série diária aceita vários anúncios e soma o gasto deles, dia a dia', () => {
    const dias = [...new Set(ba.dias.map((d) => d.dia))].sort();
    const s = serieDiariaAnuncio(trio, ba.dias, ba.linhas, dias);
    const total = ba.dias.filter((d) => trio.includes(d.anuncioId)).reduce((x, d) => x + d.gasto, 0);
    expect(s.reduce((x, d) => x + d.gasto, 0)).toBeCloseTo(total, 6);
    const so = serieDiariaAnuncio(trio[0], ba.dias, ba.linhas, dias); // texto simples continua valendo
    expect(so.reduce((x, d) => x + d.gasto, 0)).toBeLessThan(total);
  });
  it('recorte do grupo: criativo em vários anúncios manda a lista de ids do Meta; com conjunto manda o id do anúncio', () => {
    const t = { campanhas: ba.campanhas, conjuntos: ba.conjuntos, paginas: [],
      anuncios: ba.anuncios.map((a) => ({ ...a, idExterno: `meta-${a.id}` })) };
    const sem = recorteDaTela({ funil: 'todos', canal: 'todos', criativos: { anuncio: trio[0] } }, t);
    // todos os anúncios do criativo, ordenados e sem repetição, numa chamada só
    expect(sem).toEqual({ ok: true, recorte: { tipo: 'anuncio', valor: trio.map((id) => `meta-${id}`).sort().join(',') }, descricao: `Anúncio: ${NOME}` });
    // escolher qualquer um dos anúncios do criativo dá o mesmo recorte
    expect(recorteDaTela({ funil: 'todos', canal: 'todos', criativos: { anuncio: trio[2] } }, t)).toEqual(sem);
    const cj = ix.anuncio.get(trio[1])!.conjuntoId;
    const com = recorteDaTela({ funil: 'todos', canal: 'todos', criativos: { anuncio: trio[0], conjunto: cj } }, t);
    expect(com.ok).toBe(true);
    if (com.ok) expect(com.recorte).toEqual({ tipo: 'anuncio', valor: `meta-${trio[1]}` });
    // criativo de um anúncio só continua mandando o id dele
    const unico = ba.anuncios.find((a) => !trio.includes(a.id))!;
    const um = recorteDaTela({ funil: 'todos', canal: 'todos', criativos: { anuncio: unico.id } }, t);
    expect(um.ok && um.recorte).toEqual({ tipo: 'anuncio', valor: `meta-${unico.id}` });
  });
});

describe('recorte do grupo: teto de 2000 caracteres da lista de ids', () => {
  // Ids de 18 dígitos (o tamanho real do Meta): 105 dão 1994 caracteres; mais um de 5 dígitos fecha 2000 exatos.
  const id18 = (i: number) => `1${String(i).padStart(17, '0')}`;
  const tr = (ids: string[]) => ({
    campanhas: [], conjuntos: [], paginas: [],
    anuncios: ids.map((idExterno, i) => ({ id: `a${i}`, conjuntoId: `c${i}`, nome: 'MESMO NOME', formato: null, paginaId: null,
      miniaturaUrl: null, linkPrevia: null, linkGerenciador: null, idExterno })),
  }) as unknown as Parameters<typeof recorteDaTela>[1];
  const r = (ids: string[]) => recorteDaTela({ funil: 'todos', canal: 'todos', criativos: { anuncio: 'a0' } }, tr(ids));
  const ids105 = Array.from({ length: 105 }, (_, i) => id18(i));

  it('lista com exatamente 2000 caracteres vai ao servidor', () => {
    const x = r([...ids105, '12345']);
    expect(x.ok).toBe(true);
    if (x.ok) {
      expect(x.recorte?.tipo).toBe('anuncio');
      expect(x.recorte?.valor.length).toBe(TETO_RECORTE_ANUNCIO);
      expect(x.recorte?.valor.split(',')).toHaveLength(106);
    }
  });
  it('lista com 2001 caracteres não vai: Sem dado com o motivo, nunca número de outro recorte', () => {
    const x = r([...ids105, '123456']);
    expect(x.ok).toBe(false);
    if (!x.ok) {
      expect(x.motivo).toContain('2000 caracteres');
      expect(x.motivo).toContain('"MESMO NOME"');
      expect(x.motivo).toContain('106 anúncios');
    }
  });
  it('id repetido entra uma vez só e a ordem não muda a chamada', () => {
    const a = r(['300', '100', '200', '100']);
    const b2 = r(['100', '200', '300']);
    expect(a).toEqual(b2);
    expect(a.ok && a.recorte).toEqual({ tipo: 'anuncio', valor: '100,200,300' });
  });
  it('demo: a lista soma os anúncios do criativo como o servidor (cada pessoa uma vez)', () => {
    const p = { de: '2000-01-01', ate: '2999-12-31' };
    const limite = Date.parse('2999-12-31T23:59:59Z');
    const ids = [...new Set(b.linhas.map((l) => l.anuncioMeta ?? l.anuncioId).filter((x): x is string => !!x))].slice(0, 2);
    expect(ids).toHaveLength(2);
    const um = (v: string) => grupoDemo(b.linhas, p, { tipo: 'anuncio', valor: v }, limite).leads.unicos ?? 0;
    const lista = grupoDemo(b.linhas, p, { tipo: 'anuncio', valor: ids.join(',') }, limite).leads.unicos ?? 0;
    const pessoas = new Set(b.linhas.filter((l) => !l.teste && ids.includes((l.anuncioMeta ?? l.anuncioId) ?? '')).map((l) => l.pessoaId));
    expect(lista).toBe(pessoas.size);
    expect(lista).toBeGreaterThanOrEqual(Math.max(um(ids[0]), um(ids[1])));
    expect(lista).toBeLessThanOrEqual(um(ids[0]) + um(ids[1]));
  });
});

describe('criativos e páginas', () => {
  it('painel de campanhas: soma do gasto = gasto total; nome = string exata da campanha', () => {
    const itens = painel('campanha', {}, b.dias, b.linhas, idx, regua, nomePagina);
    const total = b.dias.reduce((s, d) => s + d.gasto, 0);
    expect(itens.reduce((s, i) => s + i.resumo.gasto, 0)).toBeCloseTo(total, 6);
    for (const i of itens) expect(i.nome).toBe(b.campanhas.find((c) => c.id === i.id)!.nome);
  });
  it('filtro cruzado: o painel de campanhas continua vendo as irmãs da campanha escolhida', () => {
    const f = { campanha: 'cp-iscas' };
    expect(painel('campanha', f, b.dias, b.linhas, idx, regua, nomePagina).length).toBeGreaterThan(1);
    const conj = painel('conjunto', f, b.dias, b.linhas, idx, regua, nomePagina);
    expect(conj.every((c) => b.conjuntos.find((x) => x.id === c.id)!.campanhaId === 'cp-iscas')).toBe(true);
  });
  it('escolher um conjunto filtra também as campanhas: sobra só a campanha dele, com o gasto só daquele conjunto', () => {
    const conjunto = b.conjuntos.find((c) => c.campanhaId === 'cp-iscas')!;
    const f = { conjunto: conjunto.id };
    const camp = painel('campanha', f, b.dias, b.linhas, idx, regua, nomePagina);
    expect(camp.map((c) => c.id)).toEqual(['cp-iscas']);
    const doConjunto = painel('conjunto', f, b.dias, b.linhas, idx, regua, nomePagina);
    expect(camp[0].resumo.gasto).toBeCloseTo(doConjunto.find((c) => c.id === conjunto.id)!.resumo.gasto, 6);
    // o painel de conjuntos continua vendo os irmãos do conjunto escolhido (o próprio painel só destaca)
    expect(doConjunto.length).toBeGreaterThan(1);
  });
  it('CPL do criativo = gasto ÷ leads pagos dele; C1 é distribuição (sem CPL)', () => {
    const anuncios = painel('anuncio', {}, b.dias, b.linhas, idx, regua, nomePagina);
    const capt = anuncios.find((a) => !a.resumo.distribuicao && a.resumo.leadsPagos > 0)!;
    expect(capt.resumo.cpl).toBeCloseTo(capt.resumo.gasto / capt.resumo.leadsPagos, 6);
    const c1 = anuncios.filter((a) => idx.campanhaDoAnuncio(a.id)?.funil === 'c1');
    expect(c1.length).toBeGreaterThan(0);
    expect(c1.every((a) => a.resumo.distribuicao && a.resumo.cpl === null && a.resumo.farol === 'sem')).toBe(true);
  });
  it('ordem por menor CPL deixa quem não tem CPL no fim', () => {
    const o = ordenar(painel('anuncio', {}, b.dias, b.linhas, idx, regua, nomePagina), 'cpl');
    const primeiroNulo = o.findIndex((x) => x.resumo.cpl === null);
    expect(primeiroNulo).toBeGreaterThan(0);
    expect(o.slice(primeiroNulo).every((x) => x.resumo.cpl === null)).toBe(true);
    for (let i = 1; i < primeiroNulo; i += 1) expect(o[i].resumo.cpl!).toBeGreaterThanOrEqual(o[i - 1].resumo.cpl!);
  });
  it('cada ordem da galeria ordena pelo seu valor (maior CTR, mais leads, mais gasto desc; menor CPL asc), sem dado no fim', () => {
    const itens = painel('anuncio', {}, b.dias, b.linhas, idx, regua, nomePagina);
    for (const ordem of ORDENS_GALERIA) {
      const v = ordenar(itens, ordem).map((x) => valorOrdem(x, ordem));
      const corte = v.indexOf(null) === -1 ? v.length : v.indexOf(null);
      expect(v.slice(corte).every((x) => x === null)).toBe(true);
      for (let i = 1; i < corte; i += 1) {
        if (ordem === 'cpl') expect(v[i]!).toBeGreaterThanOrEqual(v[i - 1]!);
        else expect(v[i]!).toBeLessThanOrEqual(v[i - 1]!);
      }
    }
    // As ordens mudam a galeria de verdade: o topo por CTR não é o topo por gasto.
    expect(ordenar(itens, 'ctr')[0].id).not.toBe(ordenar(itens, 'gasto')[0].id);
  });
  it('ordem por percentual MQL é decrescente e põe sem dado no fim', () => {
    const itens = painel('anuncio', {}, b.dias, b.linhas, idx, regua, nomePagina);
    const ordenados = ordenar(itens, 'mql');
    const valores = ordenados.map((x) => valorOrdem(x, 'mql'));
    const corte = valores.indexOf(null) === -1 ? valores.length : valores.indexOf(null);
    expect(valores.slice(corte).every((x) => x === null)).toBe(true);
    for (let i = 1; i < corte; i += 1) expect(valores[i]!).toBeLessThanOrEqual(valores[i - 1]!);
    const base = itens[0];
    expect(valorOrdem({ ...base, resumo: { ...base.resumo, leadsPagos: 4, mql: { ...base.resumo.mql, valor: 0.9 } } }, 'mql')).toBeNull();
    expect(valorOrdem({ ...base, resumo: { ...base.resumo, leadsPagos: 5, mql: { ...base.resumo.mql, valor: 0.9 } } }, 'mql')).toBe(0.9);
  });
  it('percentual MQL do criativo usa somente leads pagos e não inclui cadastros orgânicos', () => {
    const dias = b.dias.slice(0, 1);
    const pagos = [
      { ...b.linhas.find((l) => l.origem === 'pago')!, pessoaId: 'pago-mql', profissao: 'advogado' as const, mql: false },
      { ...b.linhas.find((l) => l.origem === 'pago')!, pessoaId: 'pago-nao-mql', profissao: 'outros' as const, mql: true },
    ];
    const organico = { ...pagos[0], pessoaId: 'organico-mql', origem: 'organico' as const, mql: true };
    expect(resumir(dias, [...pagos, organico], idx, regua, false).mql).toMatchObject({ num: 1, den: 2, valor: 0.5 });
  });
  it('série diária do anúncio fecha com o resumo', () => {
    const a = painel('anuncio', { campanha: 'cp-iscas' }, b.dias, b.linhas, idx, regua, nomePagina)[0];
    const dias = [...new Set(b.dias.map((d) => d.dia))].sort();
    const s = serieDiariaAnuncio(a.id, b.dias, b.linhas, dias);
    expect(s.reduce((x, d) => x + d.gasto, 0)).toBeCloseTo(a.resumo.gasto, 6);
  });
  it('funil do criativo (captação): 6 etapas, cada ponte é a função de metricas.ts no mesmo recorte', () => {
    const a = painel('anuncio', { campanha: 'cp-iscas' }, b.dias, b.linhas, idx, regua, nomePagina)[0];
    const dias = b.dias.filter((d) => a.anuncios.includes(d.anuncioId)); const linhas = b.linhas.filter((l) => l.anuncioId !== null && a.anuncios.includes(l.anuncioId));
    const r = resumir(dias, linhas, idx, regua, false);
    const f = funilCriativo(r, dias, linhas, idx);
    expect(f.map((e) => e.rotulo)).toEqual(['Impressões', 'Cliques', 'Views da página', 'Leads pagos', 'Total de MQL', 'Ingresso no grupo']);
    expect(f[0].ponte).toBeNull();
    expect(f[1].ponte!.taxa).toEqual(ctr(agregar(dias)));
    expect(f[1].ponte!.taxa.valor).toBeCloseTo(r.cliques! / dias.filter((d) => d.cliquesLink !== null).reduce((s, d) => s + d.impressoes, 0), 9);
    expect(f[2].ponte!.taxa).toEqual(r.connect);
    expect(f[3].ponte!.taxa).toEqual(conversaoPagina(dias, linhas, idx));
    expect(f[4].ponte!.rotulo).toBe('% de MQL');
    expect(f[4].ponte!.taxa).toEqual(mqlDoRecorte(linhas));
    expect(f[4].valor).toBe(f[4].ponte!.taxa.num);
    expect(f[5].ponte!.taxa).toEqual(ingressoGrupoGeral(linhas));
    expect(f[5].valor).toBe(f[5].ponte!.taxa.num);
  });
  it('MQL e ingresso: pessoas únicas, ingresso sobre leads gerais e MQL pela profissão mais recente', () => {
    const L = (pessoaId: string, profissao: LinhaPerfil['profissao'], entrou: string | null, criadoEm = '2026-10-05T10:00:00Z') => ({ ...b.linhas[0], leadId: `l-${pessoaId}-${criadoEm}`, pessoaId, profissao, entrouGrupoEm: entrou, criadoEm });
    const t = [L('a', 'advogado', '2026-10-05T10:00:00Z'), L('a', 'outros', null, '2026-10-05T11:00:00Z'), L('b', 'contador', '2026-10-30T10:00:00Z'), L('c', 'estudante_direito', null), L('d', null, null)];
    const m = mqlDoRecorte(t);
    expect(m.num).toBe(2); expect(m.den).toBe(4); expect(m.valor).toBeCloseTo(0.5, 9);
    const g = ingressoGrupoGeral(t); // a e b entraram, qualquer data; base = os 4 leads (não só os MQL)
    expect(g.num).toBe(2); expect(g.den).toBe(4); expect(g.valor).toBeCloseTo(0.5, 9);
    expect(mqlDoRecorte([]).valor).toBeNull(); // sem lead: Sem dado, nunca 0
    expect(ingressoGrupoGeral([]).valor).toBeNull();
  });
  it('funil do criativo (C1, distribuição): impressões → vídeo 75%', () => {
    const c1 = painel('anuncio', {}, b.dias, b.linhas, idx, regua, nomePagina).find((x) => idx.campanhaDoAnuncio(x.id)?.funil === 'c1')!;
    const f = funilCriativo(c1.resumo, [], [], idx);
    expect(f.map((e) => e.chave)).toEqual(['impressoes', 'video75']);
    expect(f[1].ponte!.taxa).toEqual(c1.resumo.video75);
  });
});
