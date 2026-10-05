import { describe, expect, it } from 'vitest';
import { linhaDoTempo } from './pessoas';
import * as demo from '../infrastructure/demo';

describe('ficha: linha do tempo junta eventos próprios e compras da Hotmart (referência)', () => {
  it('mais novo primeiro, compra sem data fica de fora', () => {
    const l = linhaDoTempo({
      eventos: [
        { id: 1, tipo: 'lead', quando: '2026-10-01T10:00:00Z', projeto: 'PB26', fonte: 'formulario', ref_tipo: null, ref_id: null, detalhe: {}, por: null },
        { id: 2, tipo: 'ativacao', quando: '2026-10-04T10:00:00Z', projeto: 'HT33', fonte: 'crm', ref_tipo: 'crm.negocios', ref_id: 'n', detalhe: { etapa: 'Ativado' }, por: 'Fulano' },
      ],
      compras: [
        { id: 'c', produto: 'Produto', status: 'APPROVED', data: '2026-10-02T10:00:00Z', preco: 1 },
        { id: 'd', produto: 'Sem data', status: null, data: null, preco: null },
      ],
    });
    expect(l.map((x) => x.titulo)).toEqual(['Ativada', 'Compra na Hotmart', 'Entrou como lead']);
    expect(l[0].detalhe).toBe('HT33 · Ativado · Fulano');
    expect(l[1].fonte).toBe('hotmart');
  });
});

describe('modo de demonstração segue as mesmas regras', () => {
  it('cadastrar quem já existe liga, não duplica', () => {
    const antes = demo.demoBuscar('exemplo', null).length;
    const r = demo.demoCadastrar({ nome: 'Diego Ramos', telefone: '(41) 9000-0004' });
    expect(r).toMatchObject({ ok: true, pessoa_id: 'p4' });
    expect(demo.demoBuscar('exemplo', null).length).toBe(antes);
  });
  it('sem identificador forte é recusado', () => {
    expect(demo.demoCadastrar({ nome: 'Só Nome' }).ok).toBe(false);
  });
  it('perda exige motivo; fechado só reabre', () => {
    expect(demo.demoMover('n3', 9, null)).toMatchObject({ ok: false, codigo: 'motivo_obrigatorio' });
    expect(demo.demoMover('n3', 9, 'Sem resposta').ok).toBe(true);
    expect(demo.demoMover('n3', 8, null)).toMatchObject({ ok: false, codigo: 'reabrir_antes' });
    expect(demo.demoMover('n3', 6, null).ok).toBe(true);
    expect(demo.demoHistorico('n3').map((h) => h.acao)).toEqual(['reaberto', 'etapa']);
  });
  it('não abre dois negócios da mesma pessoa no mesmo pipeline e projeto', () => {
    expect(demo.demoCriar({ pipeline_id: 2, pessoa_id: 'p4', projeto_id: 1 }).ok).toBe(false);
    expect(demo.demoCriar({ pipeline_id: 2, pessoa_id: 'p4', projeto_id: 2 }).ok).toBe(true);
  });
  it('revisão "é a mesma" junta os negócios e some da lista', () => {
    const n = demo.demoRevisoes().length;
    expect(demo.demoDecidir(1, 'mesma', 'p1').ok).toBe(false);
    expect(demo.demoDecidir(1, 'mesma', 'p2').ok).toBe(true);
    expect(demo.demoRevisoes().length).toBe(n - 1);
  });
  it('ficha da demonstração com aluno não lista identificadores próprios (vêm do aluno)', () => {
    const f = demo.demoFicha('p1');
    expect(f?.aluno?.turma).toBe('T40');
    expect(f?.identificadores).toEqual([]);
    expect(demo.demoMascarado(f!).pessoa.documento).toBe('*******4725');
  });
});
