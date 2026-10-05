import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import type { GpUser } from '@/shared/domain/auth';
import {
  CAMPOS_EDITAVEIS,
  ENDERECO_PARTES,
  SOCIO_NOVO_VAZIO,
  UFS,
  documentoValido,
  ehBrasil,
  enderecoDoSocioNovo,
  enderecoEmLinha,
  enderecoTemDado,
  formatarCep,
  formatarDocumento,
  normalizarTelefonePessoa,
  validarEndereco,
  validarSocioNovo,
  type SocioNovo,
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
const MIGRATION_K = fs.readFileSync(
  path.resolve(__dirname, '../../../../infra/supabase/migrations/20261005k_pedidos_socio_novo_endereco.sql'),
  'utf8',
);
/** Lê o array de uma função `returns text[]` da migration (pa_campos, pa_colunas_endereco, pa_ufs). */
function arraySql(fn: string, sql = MIGRATION): string[] {
  const m = new RegExp(`function public\\.${fn}\\(\\)[\\s\\S]*?array\\[([\\s\\S]*?)\\]`).exec(sql);
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
  it('documento: só dígitos, CPF 11 ou CNPJ 14, com dígito verificador', () => {
    expect(validarValor('documento', '529.982.247-25')).toEqual({ ok: true, valor: '52998224725' });
    expect(validarValor('documento', '12.345.678/0001-95')).toEqual({ ok: true, valor: '12345678000195' });
    expect(validarValor('documento', '1234').ok).toBe(false);
    expect(validarValor('documento', '529.982.247-24')).toEqual({ ok: false, erro: 'CPF ou CNPJ inválido: confira os dígitos.' });
  });
  it('endereço: UF da lista no Brasil, província livre no exterior', () => {
    expect(validarValor('endereco', { estado: 'XX' })).toEqual({ ok: false, erro: 'Estado inválido: escolha uma das 27 UFs (ex.: SP).' });
    const r = validarValor('endereco', { pais: 'Argentina', estado: 'Buenos Aires', cep: 'C1002' });
    expect(r.ok && (r.valor as Record<string, unknown>).estado).toBe('Buenos Aires');
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

const END_SP = { pais: 'Brasil', cep: '01001-000', endereco_logradouro: 'Praça da Sé', endereco_numero: '1',
  endereco_complemento: '', bairro: 'Sé', cidade: 'São Paulo', estado: 'sp' };

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
      novo: { ...SOCIO_NOVO_VAZIO, nome: 'Novo Sócio', email: 'novo@x.com', telefone: '21 99999-0000',
        documento: '529.982.247-25', endereco: END_SP } })).toBeNull();
  });

  it('recusa o que o banco recusaria', () => {
    expect(validarTrocaSocio({ titular: s1, sai: s1b, socios, entra: livre, novo: null })).toMatch(/Escolha o titular/);
    expect(validarTrocaSocio({ titular, sai: livre, socios, entra: s1, novo: null })).toMatch(/não é sócio/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: s1b, novo: null })).toMatch(/já é sócio deste titular/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: deOutro, novo: null })).toMatch(/outro titular/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: titular, novo: null })).toMatch(/outra pessoa/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: null, novo: null })).toMatch(/sócio que entra/);
    expect(validarTrocaSocio({ titular, sai: s1, socios, entra: null,
      novo: { ...SOCIO_NOVO_VAZIO, nome: 'Novo', email: 'ruim' } })).toMatch(/Sócio novo: E-mail inválido/);
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

describe('documento, telefone e CEP (espelho de pa_doc_valido, pa_telefone_pessoa, pa_endereco)', () => {
  it('as 27 UFs são as mesmas do banco (pa_ufs)', () => {
    expect([...UFS]).toEqual(arraySql('pa_ufs', MIGRATION_K));
    expect(UFS).toHaveLength(27);
  });
  it('CPF e CNPJ com dígito verificador', () => {
    expect(documentoValido('484.621.880-59')).toBe(true);
    expect(documentoValido('484.621.880-58')).toBe(false);
    expect(documentoValido('111.111.111-11')).toBe(false);
    expect(documentoValido('11.222.333/0001-81')).toBe(true);
    expect(documentoValido('11.222.333/0001-80')).toBe(false);
    expect(documentoValido('00000000000000')).toBe(false);
    expect(documentoValido('1234')).toBe(false);
  });
  it('máscaras de documento e CEP', () => {
    expect(formatarDocumento('48462188059')).toBe('484.621.880-59');
    expect(formatarDocumento('4846')).toBe('484.6');
    expect(formatarDocumento('11222333000181')).toBe('11.222.333/0001-81');
    expect(formatarCep('01001000')).toBe('01001-000');
    expect(formatarCep('0100')).toBe('0100');
  });
  it('telefone: Brasil 55 + DDD + número; exterior 8 a 15 dígitos', () => {
    expect(normalizarTelefonePessoa('(21) 99999-0000', true)).toEqual({ ok: true, valor: '5521999990000' });
    expect(normalizarTelefonePessoa('21 3333-4444', true)).toEqual({ ok: true, valor: '552133334444' });
    expect(normalizarTelefonePessoa('+55 21 99999-0000', true)).toEqual({ ok: true, valor: '5521999990000' });
    expect(normalizarTelefonePessoa('(01) 99999-0000', true).ok).toBe(false);
    expect(normalizarTelefonePessoa('+351 912 345 678', true).ok).toBe(false);
    expect(normalizarTelefonePessoa('+351 912 345 678', false)).toEqual({ ok: true, valor: '351912345678' });
    expect(normalizarTelefonePessoa('+351 12', false).ok).toBe(false);
    expect(normalizarTelefonePessoa('', true)).toEqual({ ok: false, erro: 'Informe o telefone.' });
  });
  it('país: vazio e variações contam como Brasil', () => {
    expect(ehBrasil(null)).toBe(true);
    expect(ehBrasil(' brasil ')).toBe(true);
    expect(ehBrasil('Brazil')).toBe(true);
    expect(ehBrasil('Portugal')).toBe(false);
  });
});

describe('validarEndereco (espelho de pa_endereco)', () => {
  it('Brasil completo: normaliza CEP, UF e país', () => {
    expect(validarEndereco(END_SP, true)).toEqual({ ok: true, valor: { cep: '01001000', endereco_logradouro: 'Praça da Sé',
      endereco_numero: '1', endereco_complemento: null, bairro: 'Sé', cidade: 'São Paulo', estado: 'SP', pais: 'Brasil' } });
  });
  it('Brasil: UF fora da lista, CEP curto e obrigatórios, com erro por campo', () => {
    const uf = validarEndereco({ ...END_SP, estado: 'XX' }, true);
    expect(uf.ok === false && uf.erros.estado).toBe('Estado inválido: escolha uma das 27 UFs (ex.: SP).');
    const cep = validarEndereco({ ...END_SP, cep: '0100100' }, true);
    expect(cep.ok === false && cep.erros.cep).toBe('CEP deve ter 8 dígitos.');
    const falta = validarEndereco({ ...END_SP, endereco_numero: '', bairro: ' ' }, true);
    expect(falta).toEqual({ ok: false, erro: 'Endereço incompleto: falta número, bairro.',
      erros: { endereco_numero: 'Obrigatório.', bairro: 'Obrigatório.' } });
  });
  it('exterior: CEP e província livres, exige endereço e cidade', () => {
    const r = validarEndereco({ pais: 'Portugal', cep: '1100-053', endereco_logradouro: 'Rua Augusta', cidade: 'Lisboa', estado: 'Lisboa' }, true);
    expect(r.ok && r.valor).toMatchObject({ cep: '1100-053', estado: 'Lisboa', pais: 'Portugal', bairro: null });
    const f = validarEndereco({ pais: 'Portugal', endereco_logradouro: 'Rua Augusta' }, true);
    expect(f.ok === false && f.erro).toBe('Endereço incompleto: falta cidade.');
  });
  it('alterar dado: parcial vale e país vazio continua vazio', () => {
    const r = validarEndereco({ cidade: 'Niterói' }, false);
    expect(r.ok && r.valor.pais).toBeNull();
  });
  it('endereço numa linha e "tem dado" ignora o país', () => {
    expect(enderecoEmLinha({ ...END_SP, cep: '01001000', estado: 'SP' })).toBe('Praça da Sé, 1, Sé, São Paulo/SP, CEP 01001-000, Brasil');
    expect(enderecoTemDado({ pais: 'Brasil' })).toBe(false);
    expect(enderecoTemDado({ pais: 'Brasil', cidade: 'Rio' })).toBe(true);
    expect(enderecoTemDado(null)).toBe(false);
  });
});

describe('pessoa nova: manter endereço do sócio que sai', () => {
  const SAI = { cep: '22290140', endereco_logradouro: 'Rua Lauro Müller', endereco_numero: '116', endereco_complemento: null,
    bairro: 'Botafogo', cidade: 'Rio de Janeiro', estado: 'RJ', pais: 'Brasil' };
  const base: SocioNovo = { ...SOCIO_NOVO_VAZIO, nome: 'Ana Nova', email: 'ana@x.com', telefone: '21 98888-7777',
    documento: '484.621.880-59', endereco: { ...SOCIO_NOVO_VAZIO.endereco } };

  it('marcado: vale o endereço de quem sai e o pedido vai sem endereço (o banco tira a foto)', () => {
    const novo = { ...base, endereco_mantido: true };
    expect(enderecoDoSocioNovo(novo, SAI)).toEqual(SAI);
    const r = validarSocioNovo(novo, SAI);
    expect(r.erros).toEqual({});
    expect(r.payload).toEqual({ nome: 'Ana Nova', email: 'ana@x.com', telefone: '5521988887777', documento: '48462188059',
      profissao: null, endereco_mantido: true, endereco: null });
  });
  it('marcado sem endereço de quem sai: recusa', () => {
    const r = validarSocioNovo({ ...base, endereco_mantido: true }, { pais: 'Brasil' });
    expect(r.erros.endereco).toMatch(/não tem endereço cadastrado/);
    expect(enderecoDoSocioNovo({ ...base, endereco_mantido: true }, null)).toEqual(base.endereco);
  });
  it('desmarcado: vale o endereço digitado, com erro ao lado de cada campo', () => {
    const vazio = validarSocioNovo(base, SAI);
    expect(vazio.payload).toBeNull();
    expect(vazio.erros.cep).toBe('Obrigatório.');
    expect(vazio.erros.estado).toBe('Obrigatório.');
    const ok = validarSocioNovo({ ...base, profissao: ' Contadora ', endereco: { ...END_SP } }, SAI);
    expect(ok.payload?.endereco).toMatchObject({ cep: '01001000', estado: 'SP', pais: 'Brasil' });
    expect(ok.payload?.profissao).toBe('Contadora');
  });
  it('documento, telefone e e-mail obrigatórios; telefone segue o país do endereço', () => {
    const r = validarSocioNovo({ ...base, documento: '', telefone: '', email: '', endereco: { ...END_SP } }, null);
    expect(r.erros).toMatchObject({ documento: 'Informe o CPF ou CNPJ.', telefone: 'Informe o telefone.', email: 'E-mail inválido.' });
    expect(validarSocioNovo({ ...base, documento: '484.621.880-58', endereco: { ...END_SP } }, null).erros.documento)
      .toBe('CPF ou CNPJ inválido: confira os dígitos.');
    const ext = { pais: 'Portugal', cep: '1100-053', endereco_logradouro: 'Rua Augusta', endereco_numero: '10',
      endereco_complemento: '', bairro: '', cidade: 'Lisboa', estado: 'Lisboa' };
    expect(validarSocioNovo({ ...base, telefone: '+351 912 345 678', endereco: ext }, null).payload?.telefone).toBe('351912345678');
    expect(validarSocioNovo({ ...base, telefone: '+351 912 345 678', endereco: { ...END_SP } }, null).erros.telefone).toMatch(/Telefone inválido/);
  });
});
