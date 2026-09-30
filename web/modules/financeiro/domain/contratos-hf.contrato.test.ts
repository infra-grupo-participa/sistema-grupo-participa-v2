// Contrato RPC ↔ tipo TS dos contratos Holding Familiar (z93): tsc e build não veem SQL. Lê a migração (ainda NÃO
// aplicada) e confere que o RETURNS TABLE das 2 leituras, as chaves do jsonb `parcelas` e as colunas novas da lista de
// informados são exatamente as que a tela lê. Prova o texto da migração, não o banco vivo.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  COLUNAS_CONTRATOS_HF_MENSAL, COLUNAS_CONTRATOS_HF_PAGAMENTOS, COLUNAS_CONTRATOS_HF_SYNC, type ParcelaContratoHF,
} from './contratos-hf';

const sql = readFileSync(fileURLToPath(new URL(
  '../../../../infra/supabase/migrations/20260930z93_fin_contratos_hf.sql', import.meta.url)), 'utf8');

/** Conteúdo entre o parêntese que abre em `ini` e o que fecha no mesmo nível. */
function entreParenteses(ini: number): string {
  let prof = 1, i = ini;
  while (prof > 0) { if (sql[i] === '(') prof++; if (sql[i] === ')') prof--; i++; }
  return sql.slice(ini, i - 1);
}

function colunasRetorno(funcao: string): string[] {
  const nome = funcao.replace(/\./g, '\\.');
  const m = new RegExp(`create\\s+(?:or\\s+replace\\s+)?function\\s+${nome}\\([^)]*\\)\\s*returns\\s+table\\s*\\(`, 'i').exec(sql);
  if (!m) throw new Error(`create function ${funcao} não encontrado`);
  return entreParenteses(m.index + m[0].length).split(',').map((c) => c.trim().split(/\s+/)[0]);
}

/** Chaves do jsonb_build_object logo depois de `jsonb_agg(` no CTE `nome as (`. */
function chavesJsonb(cte: string): string[] {
  const ini = sql.indexOf(`${cte} as (`, sql.indexOf('create function public.fn_fin_contratos_hf_mensal'));
  if (ini < 0) throw new Error(`CTE ${cte} não encontrado`);
  const j = sql.indexOf('jsonb_build_object(', ini) + 'jsonb_build_object('.length;
  const corpo = entreParenteses(j);
  return [...corpo.matchAll(/'([a-z_]+)'\s*,/g)].map((x) => x[1]);
}

const CHAVES_PARCELA: readonly (keyof ParcelaContratoHF)[] = [
  'id', 'parcela_n', 'parcela_de', 'valor', 'data_prevista', 'situacao', 'baixa_manual_em', 'transacao_hotmart', 'etapa',
  'etapa_concluida_em', 'observacao',
];

describe('contrato z93 — fn_fin_contratos_hf_*', () => {
  it('fn_fin_contratos_hf_mensal: colunas iguais ao tipo, na ordem', () => {
    expect(colunasRetorno('public.fn_fin_contratos_hf_mensal')).toEqual([...COLUNAS_CONTRATOS_HF_MENSAL]);
  });
  it('fn_fin_contratos_hf_pagamentos: colunas iguais ao tipo, na ordem', () => {
    expect(colunasRetorno('public.fn_fin_contratos_hf_pagamentos')).toEqual([...COLUNAS_CONTRATOS_HF_PAGAMENTOS]);
  });
  it('fn_fin_contratos_hf_sync_status: colunas iguais ao tipo, na ordem (1 linha sempre)', () => {
    expect(colunasRetorno('public.fn_fin_contratos_hf_sync_status')).toEqual([...COLUNAS_CONTRATOS_HF_SYNC]);
    expect(sql).toMatch(/create function public\.fn_fin_contratos_hf_sync_status\(\)/);
  });
  it('parcelas (jsonb) do mês: as chaves que a tela lê; etapa: subconjunto com situacao', () => {
    expect(chavesJsonb('esp')).toEqual([...CHAVES_PARCELA]);
    const etp = chavesJsonb('etp');
    expect(etp).toEqual(['id', 'parcela_n', 'parcela_de', 'valor', 'etapa', 'situacao']);
    expect(etp.every((k) => (CHAVES_PARCELA as readonly string[]).includes(k))).toBe(true);
  });
  it('assinaturas das escritas que o repositório chama (nomes dos parâmetros)', () => {
    expect(sql).toMatch(/create function public\.fn_fin_contrato_hf_salvar\(p jsonb\)/);
    expect(sql).toMatch(/create function public\.fn_fin_parcela_etapa_concluir\(p_id uuid, p_data date\)/);
    expect(sql).toMatch(/create function public\.fn_fin_contrato_hf_desfundir\(p_id uuid, p_motivo text\)/);
    expect(sql).toMatch(/create function public\.fn_fin_contratos_hf_mensal\(p_de date default null, p_ate date default null\)/);
    expect(sql).toMatch(/create function public\.fn_fin_contratos_hf_pagamentos\(p_so_fila boolean default true\)/);
  });
  it('fn_fin_informados_listar ganha contrato_id, etapa, etapa_concluida_em, transacao_hotmart, observacao no FIM (normalizarInformado lê)', () => {
    expect(sql.replace(/\s+/g, ' ')).toContain(
      'contrato_assinado boolean, contrato_id uuid, etapa text, etapa_concluida_em date, transacao_hotmart text, observacao text)');
    expect(sql).toMatch(/r\.contrato_id, r\.etapa, r\.etapa_concluida_em, r\.transacao_hotmart, r\.observacao/);
  });
  it('link do contrato: a regex da tela é a MESMA do banco (texto a texto)', () => {
    const m = /n\.link_contrato !~ '([^']+)'/.exec(sql);
    expect(m).not.toBeNull();
    const ts = readFileSync(fileURLToPath(new URL('./contratos-hf.ts', import.meta.url)), 'utf8');
    const reTs = /const LINK_OK = \/(.+)\/;/.exec(ts)?.[1];
    expect(reTs?.replace(/\\\//g, '/')).toBe(m![1]);
  });
});
