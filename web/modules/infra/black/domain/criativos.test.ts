import { describe, expect, it } from 'vitest';
import { baseFicticia } from '../infrastructure/fixtures/gerador';
import { CONFIG_BLACK } from '../infrastructure/fixtures/catalogo';
import { conversaoPagina, ctr, agregar, indexar, ingressoGrupo } from './metricas';
import { anunciosDoCriativo, funilCriativo, idDoCriativo, ORDENS_GALERIA, ordenar, painel, resumir, serieDiariaAnuncio, valorOrdem } from './criativos';
import { recorteDaTela } from './grupo';

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
  it('recorte do grupo: criativo em vários anúncios sem conjunto avisa; com conjunto manda o id do Meta do anúncio', () => {
    const t = { campanhas: ba.campanhas, conjuntos: ba.conjuntos, paginas: [],
      anuncios: ba.anuncios.map((a) => ({ ...a, idExterno: `meta-${a.id}` })) };
    const sem = recorteDaTela({ funil: 'todos', canal: 'todos', criativos: { anuncio: trio[0] } }, t);
    expect(sem.ok).toBe(false);
    if (!sem.ok) expect(sem.motivo).toContain('Escolha também um conjunto');
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
  it('série diária do anúncio fecha com o resumo', () => {
    const a = painel('anuncio', { campanha: 'cp-iscas' }, b.dias, b.linhas, idx, regua, nomePagina)[0];
    const dias = [...new Set(b.dias.map((d) => d.dia))].sort();
    const s = serieDiariaAnuncio(a.id, b.dias, b.linhas, dias);
    expect(s.reduce((x, d) => x + d.gasto, 0)).toBeCloseTo(a.resumo.gasto, 6);
  });
  it('funil do criativo (captação): 5 etapas, cada ponte é a função de metricas.ts no mesmo recorte', () => {
    const a = painel('anuncio', { campanha: 'cp-iscas' }, b.dias, b.linhas, idx, regua, nomePagina)[0];
    const dias = b.dias.filter((d) => d.anuncioId === a.id); const linhas = b.linhas.filter((l) => l.anuncioId === a.id);
    const agora = new Date('2026-11-04T12:00:00-03:00');
    const r = resumir(dias, linhas, idx, regua, false);
    const f = funilCriativo(r, dias, linhas, idx, agora);
    expect(f.map((e) => e.rotulo)).toEqual(['Impressões', 'Cliques', 'Views da página', 'Leads pagos', 'Ingresso no grupo (48h)']);
    expect(f[0].ponte).toBeNull();
    expect(f[1].ponte!.taxa).toEqual(ctr(agregar(dias)));
    expect(f[1].ponte!.taxa.valor).toBeCloseTo(r.cliques! / dias.filter((d) => d.cliquesLink !== null).reduce((s, d) => s + d.impressoes, 0), 9);
    expect(f[2].ponte!.taxa).toEqual(r.connect);
    expect(f[3].ponte!.taxa).toEqual(conversaoPagina(dias, linhas, idx));
    expect(f[4].ponte!.taxa).toEqual(ingressoGrupo(linhas, 48, agora));
    expect(f[4].valor).toBe(f[4].ponte!.taxa.num);
  });
  it('funil do criativo (C1, distribuição): impressões → vídeo 75%', () => {
    const c1 = painel('anuncio', {}, b.dias, b.linhas, idx, regua, nomePagina).find((x) => idx.campanhaDoAnuncio(x.id)?.funil === 'c1')!;
    const f = funilCriativo(c1.resumo, [], [], idx, new Date());
    expect(f.map((e) => e.chave)).toEqual(['impressoes', 'video75']);
    expect(f[1].ponte!.taxa).toEqual(c1.resumo.video75);
  });
});
