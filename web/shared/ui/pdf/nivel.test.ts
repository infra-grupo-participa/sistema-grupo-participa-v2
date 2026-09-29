import { describe, expect, it } from 'vitest';
import type { RascunhoRelatorio } from './modelo';
import {
  LINHAS_MAX_NO_PDF, aplicarNivel, contarLinhasDetalhe, excedeLimiteDoPdf, mascararDocumento, niveisDoRelatorio, prepararParaPdf,
} from './nivel';

/** Modelo genérico com as 4 classes de coluna e uma seção de resumo. */
function rascunho(over: Partial<RascunhoRelatorio> = {}): RascunhoRelatorio {
  return {
    tipo: 'pessoas', titulo: 'Teste', arquivo: 'teste',
    niveisPermitidos: ['completo', 'sem_dado_pessoal', 'so_numeros'],
    recorte: [{ rotulo: 'Família', valor: 'HM' }, { rotulo: 'Busca', valor: '"Maria Souza"', pii: true }],
    kpis: [{ rotulo: 'Pessoas', valor: '2' }],
    secoes: [
      {
        titulo: 'Resumo', tipo: 'resumo',
        colunas: [{ chave: 'sit', rotulo: 'Situação', tipo: 'texto', pii: 'nenhuma' }, { chave: 'q', rotulo: 'Pessoas', tipo: 'numero', pii: 'nenhuma' }],
        linhas: [{ celulas: { sit: 'Ativo', q: '2' } }],
      },
      {
        titulo: 'Pessoas', tipo: 'detalhe', linhasSaoPessoas: true,
        colunas: [
          { chave: 'nome', rotulo: 'Nome', tipo: 'texto', pii: 'identificacao' },
          { chave: 'email', rotulo: 'E-mail', tipo: 'texto', pii: 'contato' },
          { chave: 'tel', rotulo: 'Telefone', tipo: 'texto', pii: 'contato' },
          { chave: 'doc', rotulo: 'Documento', tipo: 'texto', pii: 'documento' },
          { chave: 'pago', rotulo: 'Pago', tipo: 'moeda', pii: 'nenhuma' },
        ],
        linhas: [
          { celulas: { nome: 'Maria Souza', email: 'maria@x.com', tel: '(11) 99999-1111', doc: '12345678901', pago: 'R$ 10' } },
          { celulas: { nome: 'João Lima', email: 'joao@x.com', tel: '', doc: 'CPF ···4321', pago: 'R$ 20' } },
        ],
        total: { nome: 'Total', pago: 'R$ 30' },
      },
    ],
    ...over,
  };
}

describe('mascararDocumento', () => {
  it('mascara CPF/CNPJ cru, com ou sem pontuação, e preserva o já mascarado', () => {
    expect(mascararDocumento('12345678901')).toBe('···8901');
    expect(mascararDocumento('123.456.789-01')).toBe('···8901');
    expect(mascararDocumento('12.345.678/0001-90')).toBe('···0190');
    expect(mascararDocumento('CPF 12345678901')).toBe('CPF ···8901');
    expect(mascararDocumento('CPF ···4321')).toBe('CPF ···4321');
    expect(mascararDocumento('Mesmo nome')).toBe('Mesmo nome');
  });
});

describe('aplicarNivel', () => {
  it('completo: mantém nome/e-mail/telefone e mascara o documento (mesmo cru na entrada)', () => {
    const r = aplicarNivel(rascunho(), 'completo');
    const det = r.secoes[1];
    expect(det.colunas.map((c) => c.chave)).toEqual(['nome', 'email', 'tel', 'doc', 'pago']);
    expect(det.linhas[0].celulas).toMatchObject({ nome: 'Maria Souza', email: 'maria@x.com', tel: '(11) 99999-1111', doc: '···8901' });
    expect(det.linhas[1].celulas.doc).toBe('CPF ···4321');
    expect(JSON.stringify(r)).not.toMatch(/\d{11}/);
    expect(r.recorte).toEqual(['Família: HM', 'Busca: "Maria Souza"']);
  });

  it('sem_dado_pessoal: some toda coluna pessoal e as pessoas viram "Pessoa N" na ordem da lista', () => {
    const r = aplicarNivel(rascunho(), 'sem_dado_pessoal');
    const det = r.secoes[1];
    expect(det.colunas.map((c) => c.rotulo)).toEqual(['Pessoa', 'Pago']);
    expect(det.linhas.map((l) => l.celulas)).toEqual([
      { __pessoa: 'Pessoa 1', pago: 'R$ 10' },
      { __pessoa: 'Pessoa 2', pago: 'R$ 20' },
    ]);
    expect(det.total).toEqual({ pago: 'R$ 30' });
    const tudo = JSON.stringify(r);
    for (const pii of ['Maria', 'maria@x.com', 'João', '99999', '8901', '4321']) expect(tudo).not.toContain(pii);
    expect(r.recorte).toEqual(['Família: HM', 'Busca: termo omitido']);
  });

  it('coluna anonimavel: completo leva o original; sem_dado_pessoal leva o substituto da linha (ou vazio), nunca o original', () => {
    const base = rascunho();
    const det0 = base.secoes[1];
    det0.linhasSaoPessoas = false;
    det0.colunas[0] = { ...det0.colunas[0], anonimavel: true };
    det0.linhas[0].anonimas = { nome: 'Pessoa 7' }; // 2ª linha sem substituto
    expect(aplicarNivel(base, 'completo').secoes[1].linhas[0].celulas.nome).toBe('Maria Souza');
    const det = aplicarNivel(base, 'sem_dado_pessoal').secoes[1];
    expect(det.colunas.map((c) => [c.chave, c.pii])).toEqual([['nome', 'nenhuma'], ['pago', 'nenhuma']]);
    expect(det.linhas.map((l) => l.celulas)).toEqual([{ nome: 'Pessoa 7', pago: 'R$ 10' }, { nome: '', pago: 'R$ 20' }]);
    expect(det.total).toEqual({ pago: 'R$ 30' }); // o "Total" da coluna pessoal não passa
    const tudo = JSON.stringify(det);
    for (const pii of ['Maria', 'João']) expect(tudo).not.toContain(pii);
    expect(aplicarNivel(base, 'so_numeros').secoes.every((s) => s.tipo === 'resumo')).toBe(true);
  });

  it('recusa coluna anonimavel em seção de resumo', () => {
    const base = rascunho();
    base.secoes[0].colunas[0] = { ...base.secoes[0].colunas[0], anonimavel: true };
    expect(() => aplicarNivel(base, 'completo')).toThrow(/anonimavel/);
  });

  it('sem_dado_pessoal em seção que não é de pessoas: só remove a coluna, sem pseudônimo', () => {
    const base = rascunho();
    base.secoes[1].linhasSaoPessoas = false;
    const det = aplicarNivel(base, 'sem_dado_pessoal').secoes[1];
    expect(det.colunas.map((c) => c.chave)).toEqual(['pago']);
  });

  it('so_numeros: nenhuma seção de detalhe; ficam KPIs e resumo', () => {
    const r = aplicarNivel(rascunho(), 'so_numeros');
    expect(r.secoes.map((s) => s.tipo)).toEqual(['resumo']);
    expect(r.kpis).toEqual([{ rotulo: 'Pessoas', valor: '2' }]);
    expect(JSON.stringify(r)).not.toContain('Maria');
  });

  it('recusa nível que o relatório não aceita (Mesma pessoa? = só completo)', () => {
    const r = rascunho({ tipo: 'identidade', niveisPermitidos: ['completo'] });
    expect(() => aplicarNivel(r, 'sem_dado_pessoal')).toThrow(/não aceita/);
    expect(() => aplicarNivel(r, 'so_numeros')).toThrow(/não aceita/);
    expect(niveisDoRelatorio(r)).toEqual(['completo']);
  });

  it('recusa seção de resumo com coluna pessoal (resumo sobrevive a todos os níveis)', () => {
    const r = rascunho();
    r.secoes[0].colunas.push({ chave: 'nome', rotulo: 'Nome', tipo: 'texto', pii: 'identificacao' });
    expect(() => aplicarNivel(r, 'so_numeros')).toThrow(/resumo/);
  });

  it('conta as linhas de detalhe (vai para a emissão)', () => {
    expect(contarLinhasDetalhe(rascunho())).toBe(2);
  });
});

describe('prepararParaPdf: limite de linhas do PDF (LINHAS_MAX_NO_PDF)', () => {
  const comLinhas = (n: number, over: Partial<RascunhoRelatorio> = {}) => {
    const r = rascunho(over);
    const base = r.secoes[1].linhas[0];
    r.secoes[1].linhas = Array.from({ length: n }, () => ({ celulas: { ...base.celulas } }));
    return r;
  };

  it('o limite é 2.000', () => expect(LINHAS_MAX_NO_PDF).toBe(2000));

  for (const nivel of ['completo', 'sem_dado_pessoal'] as const) {
    it(`${nivel} · 2.001 linhas: só cabeçalho, KPIs e resumo, com aviso; nada pessoal; 0 linhas impressas`, () => {
      const p = prepararParaPdf(comLinhas(2001, { temPlanilha: true }), nivel);
      expect(p.linhasDaLista).toBe(2001);
      expect(p.linhasImpressas).toBe(0);
      expect(p.documento.secoes.map((s) => s.tipo)).toEqual(['resumo']);
      expect(p.documento.secoes).toEqual(aplicarNivel(comLinhas(2001), 'so_numeros').secoes); // o mesmo resumo do só números
      expect(p.documento.kpis).toEqual([{ rotulo: 'Pessoas', valor: '2' }]);
      expect(p.documento.avisoSoTotais).toBe('Lista completa com 2.001 linhas disponível na exportação em planilha deste relatório.');
      expect(p.documento.nivel).toBe(nivel); // o protocolo registra o nível pedido
      const tudo = JSON.stringify(p.documento);
      for (const pii of ['Maria', 'maria@x.com', '99999', '8901']) expect(tudo).not.toContain(pii);
      expect(p.documento.recorte).toEqual(['Família: HM', 'Busca: termo omitido']);
    });

    it(`${nivel} · 2.000 linhas: PDF completo, sem aviso`, () => {
      const p = prepararParaPdf(comLinhas(2000), nivel);
      expect(p.linhasImpressas).toBe(2000);
      expect(p.documento.avisoSoTotais).toBeUndefined();
      expect(p.documento.secoes.map((s) => s.tipo)).toEqual(['resumo', 'detalhe']);
      expect(p.documento).toEqual(aplicarNivel(comLinhas(2000), nivel));
    });
  }

  it('so_numeros: nunca imprime linha e não precisa de aviso, com qualquer tamanho de lista', () => {
    const p = prepararParaPdf(comLinhas(9228), 'so_numeros');
    expect(p).toMatchObject({ linhasDaLista: 9228, linhasImpressas: 0 });
    expect(p.documento.avisoSoTotais).toBeUndefined();
    expect(excedeLimiteDoPdf(9228, 'so_numeros')).toBe(false);
  });

  it('relatório sem planilha na tela: o aviso aponta para a tela, não para planilha que não existe', () => {
    expect(prepararParaPdf(comLinhas(2001), 'completo').documento.avisoSoTotais)
      .toBe('Lista completa com 2.001 linhas disponível na tela deste relatório.');
  });

  it('"Mesma pessoa?" (só nível completo) também respeita o limite', () => {
    const r = comLinhas(2001, { tipo: 'identidade', niveisPermitidos: ['completo'] });
    const p = prepararParaPdf(r, 'completo');
    expect(p.linhasImpressas).toBe(0);
    expect(p.documento.secoes.every((s) => s.tipo === 'resumo')).toBe(true);
  });
});
