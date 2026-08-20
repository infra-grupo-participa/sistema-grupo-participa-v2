import { describe, expect, it } from 'vitest';
import type { Aluno360 } from './aluno-360';
import { vinculoSocio } from '../ui/alunos-ui-shared';

const p = (id: string, nome: string, extra: Partial<Aluno360> = {}): Aluno360 =>
  ({ id, nome, eh_socio: false, socio_de_nome: null, socio_de_aluno_id: null, ...extra }) as Aluno360;

describe('vinculoSocio', () => {
  const titular = p('t1', 'Vivaldo Moreira Cruz Junior');
  const socioComId = p('s1', 'Rony Jose Morais', { eh_socio: true, socio_de_aluno_id: 't1', socio_de_nome: 'Vivaldo Moreira Cruz Junior' });
  const socioSoNome = p('s2', 'Outra Pessoa', { eh_socio: true, socio_de_nome: 'vivaldo moreira cruz junior' });
  const base = [titular, socioComId, socioSoNome];

  it('acha o titular pelo id', () => {
    expect(vinculoSocio(socioComId, base).titular?.id).toBe('t1');
  });

  it('acha o titular pelo nome quando não há id, ignorando acento e caixa', () => {
    const v = vinculoSocio(p('s3', 'X', { eh_socio: true, socio_de_nome: 'VIVALDO MOREIRA CRUZ JÚNIOR' }), base);
    // "Júnior" com acento contra "Junior" sem: a normalização tem de casar os dois.
    expect(v.titular?.id).toBe('t1');
  });

  it('lista os sócios quando a pessoa é titular', () => {
    const v = vinculoSocio(titular, base);
    expect(v.socios.map((s) => s.id).sort()).toEqual(['s1', 's2']);
    expect(v.titular).toBeNull();
  });

  it('devolve o nome do titular mesmo quando ele não está na base', () => {
    const orfao = p('s9', 'Sozinho', { eh_socio: true, socio_de_nome: 'Titular Fora Da Central' });
    const v = vinculoSocio(orfao, [orfao]);
    expect(v.titularNome).toBe('Titular Fora Da Central');
    expect(v.titular).toBeNull();
  });

  it('não devolve a própria pessoa como titular nem como sócia', () => {
    // Registro que aponta para o próprio nome não pode virar sócio de si mesmo.
    const eu = p('x1', 'Fulano de Tal', { eh_socio: true, socio_de_nome: 'Fulano de Tal' });
    const v = vinculoSocio(eu, [eu]);
    expect(v.titular).toBeNull();
    expect(v.socios).toHaveLength(0);
  });

  it('titular sem nome não arrasta sócios de nome vazio', () => {
    const semNome = p('n1', '');
    const outro = p('n2', 'Alguém', { eh_socio: true, socio_de_nome: null });
    expect(vinculoSocio(semNome, [semNome, outro]).socios).toHaveLength(0);
  });
});
