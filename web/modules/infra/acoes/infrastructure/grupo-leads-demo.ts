import type { LeadGrupoAtm } from '@/modules/infra/atm/domain/dashboard';

/** Massa sintética para revisar a tabela antes e depois da publicação da RPC. Sem contatos reais. */
export const ENTRADAS_GRUPO_ACAO_DEMO: LeadGrupoAtm[] = [
  ...Array.from({ length: 10 }, (_, i) => {
    const n = String(i + 1).padStart(2, '0');
    return {
      foneGrupo: `000000000${n}`, origem: 'lista_disparo' as const, naLista: true, naBase: false,
      nome: `Contato fictício ${n}`, email: `contato-${n}@example.invalid`, telefone: `000000000${n}`,
      turma: 'THB', instrucao: i % 2 === 0 ? 'THB' : 'THB sócio',
      entrouEm: `2026-10-${String(15 - i).padStart(2, '0')}T15:00:00-03:00`, saiuEm: null, noGrupo: true,
      entradaAproximada: false,
    };
  }),
  {
    foneGrupo: '00000000011', origem: 'base_leads', naLista: false, naBase: true,
    nome: 'Lead fictício', email: 'lead@example.invalid', telefone: '00000000011', turma: null, instrucao: null,
    entrouEm: '2026-10-05T15:00:00-03:00', saiuEm: '2026-10-06T15:00:00-03:00', noGrupo: false, entradaAproximada: true,
  },
  ...['12', '13'].map((n) => ({
    foneGrupo: `000000000${n}`, origem: 'nao_encontrado' as const, naLista: null, naBase: null,
    nome: null, email: null, telefone: `000000000${n}`, turma: null, instrucao: null,
    entrouEm: null, saiuEm: null, noGrupo: null, entradaAproximada: null,
  })),
];
