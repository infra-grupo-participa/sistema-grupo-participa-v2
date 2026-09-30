import { describe, expect, it } from 'vitest';
import {
  FILTRO_A_REVISAR, aRevisar, normalizarProgramas, ordenarProgramas, passaFiltroComprovacao, passaFiltroPrograma,
  rotuloMotivo, textoSelo, type ProgramaAluno, type SeloNivel,
} from './programa-selo';

const prog = (x: Partial<ProgramaAluno> = {}): ProgramaAluno => ({ aluno_id: 'a', programas: [], status_programa: {}, revisar_motivos: [], ...x });
const selo = (x: Partial<SeloNivel> = {}): SeloNivel => ({ aluno_id: 'a', nivel_comprovado: null, comprovado_em: null, selo: null, ...x });

describe('programa-selo', () => {
  it('ordena na ordem fixa; desconhecido no fim', () => {
    expect(ordenarProgramas(['xpto', 'aurum', 'implementacao', 'hm'])).toEqual(['implementacao', 'hm', 'aurum', 'xpto']);
  });

  it('A revisar: por status ou por motivo', () => {
    expect(aRevisar(prog({ status_programa: { aurum: 'a_revisar' } }))).toBe(true);
    expect(aRevisar(prog({ revisar_motivos: ['aurum_so_cadastro'] }))).toBe(true);
    expect(aRevisar(prog({ status_programa: { hm: 'confirmado' } }))).toBe(false);
    expect(aRevisar(undefined)).toBe(false);
  });

  it('filtro Programa: OR entre opções; sem linha na RPC não passa', () => {
    const p = prog({ programas: ['hm'], revisar_motivos: ['x'] });
    expect(passaFiltroPrograma(p, [])).toBe(true);
    expect(passaFiltroPrograma(p, ['hm'])).toBe(true);
    expect(passaFiltroPrograma(p, ['aurum'])).toBe(false);
    expect(passaFiltroPrograma(p, ['aurum', FILTRO_A_REVISAR])).toBe(true);
    expect(passaFiltroPrograma(undefined, ['hm'])).toBe(false);
  });

  it('filtro Comprovação pelo selo cru', () => {
    expect(passaFiltroComprovacao(selo({ selo: 'comprovado' }), ['comprovado'])).toBe(true);
    expect(passaFiltroComprovacao(selo({ selo: null }), ['comprovado'])).toBe(false);
    expect(passaFiltroComprovacao(undefined, [])).toBe(true);
  });

  it('texto do selo', () => {
    expect(textoSelo('ouro', selo({ selo: 'comprovado' }))).toBe('Ouro · comprovado');
    expect(textoSelo('ouro', selo({ selo: 'outro_nivel', nivel_comprovado: 'platina' }))).toBe('Ouro · comprovado Platina');
    expect(textoSelo('ouro', selo({ selo: 'nao_comprovado' }))).toBe('Ouro · sem comprovação');
    expect(textoSelo('pessoal', selo({ selo: null }))).toBeNull();
    expect(textoSelo('ouro', undefined)).toBeNull();
  });

  it('normaliza linha crua e rotula motivo desconhecido sem sublinhado', () => {
    expect(normalizarProgramas([{ aluno_id: 'a', programas: null, status_programa: null, revisar_motivos: ['m', 1] }, { x: 1 }]))
      .toEqual([{ aluno_id: 'a', programas: [], status_programa: {}, revisar_motivos: ['m'] }]);
    expect(rotuloMotivo('algo_novo')).toBe('algo novo');
  });
});
