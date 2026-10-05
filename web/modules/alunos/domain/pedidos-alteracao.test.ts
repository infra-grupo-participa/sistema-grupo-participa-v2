import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import type { GpUser } from '@/shared/domain/auth';
import {
  CAMPOS_EDITAVEIS,
  ENDERECO_PARTES,
  instrucaoDoSocio,
  podePedirAlteracao,
  resumoPedido,
  validarMotivoEvidencia,
  validarTrocaSocio,
  validarValor,
  type AlunoResumo,
} from './pedidos-alteracao';

const MIGRATION = fs.readFileSync(
  path.resolve(__dirname, '../../../../infra/supabase/migrations/20261005j_pedidos_alteracao.sql'),
  'utf8',
);
/** Lê o array de uma função `returns text[]` da migration (pa_campos, pa_colunas_endereco). */
function arraySql(fn: string): string[] {
  const m = new RegExp(`function public\\.${fn}\\(\\)[\\s\\S]*?array\\[([\\s\\S]*?)\\]`).exec(MIGRATION);
  if (!m) throw new Error(`${fn} não encontrada na migration`);
  return [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
}

const user = (cargo: GpUser['cargo'], setores: string[] = []): GpUser =>
  ({ id: 'u', nome: '', email: '', cargo, status: 'ativo', setores, funcoes: [], podeVerCpf: false, time: null, avatarUrl: null });

describe('lista fechada de campos', () => {
  it('é a mesma do banco (pa_campos), na mesma ordem', () => {
    expect(CAMPOS_EDITAVEIS.map((c) => c.campo)).toEqual(arraySql('pa_campos'));
  });
  it('endereço tem as mesmas partes do banco (pa_colunas_endereco)', () => {
    expect(ENDERECO_PARTES.map((p) => p.k)).toEqual(arraySql('pa_colunas_endereco'));
  });
  it('nunca inclui dinheiro, compra ou Hotmart', () => {
    const proibidos = /valor|saldo|pag|cobranc|compra|hotmart|comprador|oferta|produto|financeir/;
    for (const c of CAMPOS_EDITAVEIS) expect(c.campo).not.toMatch(proibidos);
    expect(validarValor('valor_pago', '1')).toEqual({ ok: false, erro: 'Campo fora da lista de campos editáveis.' });
    expect(validarValor('hotmart_ucode', 'x').ok).toBe(false);
  });
});

describe('validarValor (espelho de pa_normalizar)', () => {
  it('nome: espaços colapsados, 3 a 200', () => {
    expect(validarValor('nome', '  Ana   Maria ')).toEqual({ ok: true, valor: 'Ana Maria' });
    expect(validarValor('nome', 'Al').ok).toBe(false);
  });
  it('e-mail: formato, sem mudar a caixa', () => {
    expect(validarValor('email', ' Rolf@Brietzig.adv.br ')).toEqual({ ok: true, valor: 'Rolf@Brietzig.adv.br' });
    expect(validarValor('email', 'sem-arroba').ok).toBe(false);
    expect(validarValor('email', '').ok).toBe(false);
  });
  it('telefone: padrão da Central com 55; vazio limpa', () => {
    expect(validarValor('telefone', '(21) 99999-0000')).toEqual({ ok: true, valor: '5521999990000' });
    expect(validarValor('telefone', '5521999990000')).toEqual({ ok: true, valor: '5521999990000' });
    expect(validarValor('telefone_profissional', '')).toEqual({ ok: true, valor: null });
    expect(validarValor('telefone', '123').ok).toBe(false);
  });
  it('documento: só dígitos, CPF 11 ou CNPJ 14', () => {
    expect(validarValor('documento', '529.982.247-25')).toEqual({ ok: true, valor: '52998224725' });
    expect(validarValor('documento', '12.345.678/0001-95')).toEqual({ ok: true, valor: '12345678000195' });
    expect(validarValor('documento', '1234').ok).toBe(false);
  });
  it('endereço: CEP 8 dígitos, UF maiúscula, partes vazias viram null', () => {
    const r = validarValor('endereco', { cep: '24.000-000', cidade: 'Niterói', estado: 'rj', bairro: '  ' });
    expect(r).toEqual({ ok: true, valor: { cep: '24000000', endereco_logradouro: null, endereco_numero: null,
      endereco_complemento: null, bairro: null, cidade: 'Niterói', estado: 'RJ', pais: null } });
    expect(validarValor('endereco', { cep: '123' }).ok).toBe(false);
    expect(validarValor('endereco', { estado: 'Rio' }).ok).toBe(false);
  });
  it('instrução: só as 12 da Central', () => {
    expect(validarValor('instrucao', 'aurum - sócio')).toEqual({ ok: true, valor: 'AURUM - SÓCIO' });
    expect(validarValor('instrucao', 'OURO').ok).toBe(false);
  });
  it('espaço e turma', () => {
    expect(validarValor('espaco_instrucao', 'aurum').ok).toBe(true);
    expect(validarValor('espaco_instrucao', 'Aurum').ok).toBe(false);
    expect(validarValor('turma_id', '40')).toEqual({ ok: true, valor: 40 });
    expect(validarValor('turma_id', 'T40').ok).toBe(false);
  });
});

describe('motivo e evidência', () => {
  it('motivo obrigatório, evidência só link', () => {
    expect(validarMotivoEvidencia('oi', '')).toMatch(/motivo/);
    expect(validarMotivoEvidencia('pediu por e-mail', 'print.png')).toMatch(/link/);
    expect(validarMotivoEvidencia('pediu por e-mail', 'https://drive.google.com/x')).toBeNull();
    expect(validarMotivoEvidencia('pediu por e-mail', '')).toBeNull();
  });
});

describe('quem pode pedir (espelho de pa_pode_pedir)', () => {
  it('dev/admin sempre; gestor/operador só com a área; visualizador nunca', () => {
    expect(podePedirAlteracao(user('admin'))).toBe(true);
    expect(podePedirAlteracao(user('dev'))).toBe(true);
    expect(podePedirAlteracao(user('operador', ['pedidos_alteracao']))).toBe(true);
    expect(podePedirAlteracao(user('gestor', ['pedidos_alteracao']))).toBe(true);
    expect(podePedirAlteracao(user('operador', ['centro_controle']))).toBe(false);
    expect(podePedirAlteracao(user('visualizador', ['pedidos_alteracao']))).toBe(false);
    expect(podePedirAlteracao(null)).toBe(false);
  });
});

describe('vínculo de sócio na troca', () => {
  const r = (id: string, nome: string, extra: Partial<AlunoResumo> = {}): AlunoResumo => ({
    id, nome, instrucao: null, espaco: null, eh_socio: false, titular_nome: null, titular_id: null, turma: null,
    email: null, telefone_final: null, doc_final: null, num_socios: null, ...extra,
  });
  const titular = r('t', 'Titular');
  const s1 = r('s1', 'Sócio Um', { eh_socio: true, titular_id: 't', titular_nome: 'Titular' });
  const s1b = r('s1b', 'Sócio Só Nome', { eh_socio: true, titular_nome: 'Titular' });
  const livre = r('x', 'Livre');
  const deOutro = r('y', 'De Outro', { eh_socio: true, titular_id: 'z', titular_nome: 'Outro' });
  const socios = [s1, s1b];

  it('sócio acompanha a instrução do titular', () => {
    expect(instrucaoDoSocio({ instrucao: 'AURUM', espaco_instrucao: 'aurum' })).toBe('AURUM - SÓCIO');
    expect(instrucaoDoSocio({ instrucao: 'THB IMPLEMENTACAO', espaco_instrucao: null })).toBe('THB IMPLEMENTAÇÃO - SÓCIO');
    // Sem instrução: vem do espaço (como na Central).
    expect(instrucaoDoSocio({ instrucao: null, espaco_instrucao: 'mastermind_diamante' })).toBe('DIAMANTE - SÓCIO');
    expect(instrucaoDoSocio({ instrucao: null, espaco_instrucao: null })).toBeNull();
  });

  it('troca válida com sócio existente ou novo', () => {
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: livre, novo: null })).toBeNull();
    // Sócio vinculado só pelo nome também pode sair.
    expect(validarTrocaSocio({ titular, sai: s1b, socios, entra: null,
      novo: { nome: 'Novo Sócio', email: 'novo@x.com', telefone: '21 99999-0000', documento: '' } })).toBeNull();
  });

  it('recusa o que o banco recusaria', () => {
    expect(validarTrocaSocio({ titular: s1, sai: s1b, socios, entra: livre, novo: null })).toMatch(/Escolha o titular/);
    expect(validarTrocaSocio({ titular, sai: livre, socios, entra: s1, novo: null })).toMatch(/não é sócio/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: s1b, novo: null })).toMatch(/já é sócio deste titular/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: deOutro, novo: null })).toMatch(/outro titular/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: titular, novo: null })).toMatch(/outra pessoa/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: null, novo: null })).toMatch(/sócio que entra/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: null,
      novo: { nome: 'Novo', email: 'ruim', telefone: '', documento: '' } })).toMatch(/E-mail/);
  });
});

describe('resumoPedido', () => {
  it('descreve cada tipo', () => {
    const base = { campo: null, de: null, para: null, socio_sai_nome: null, socio_entra_nome: null, descricao: null };
    expect(resumoPedido({ ...base, tipo: 'alterar_dado', campo: 'email', de: 'a@x.com', para: 'b@x.com' })).toBe('E-mail: a@x.com → b@x.com');
    expect(resumoPedido({ ...base, tipo: 'trocar_socio', socio_sai_nome: 'A', socio_entra_nome: 'B' })).toBe('Sai A, entra B');
    expect(resumoPedido({ ...base, tipo: 'outro', descricao: 'Juntar cadastros' })).toBe('Juntar cadastros');
  });
});
