import { describe, it, expect } from 'vitest';
import {
  faturamentoBlockReason,
  isPlateEligible,
  isTokenDocumentUrl,
  nivelRefazerBlockReason,
  nivelSugeridoPorFaturamento,
  validateFormProgress,
} from './form-progress';

const TOKEN = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const proof = `https://x.supabase.co/storage/v1/object/public/documentos/placas/${TOKEN}/proof_1.pdf`;
const decl = `https://x.supabase.co/storage/v1/object/public/documentos/placas/${TOKEN}/declaracao_1.pdf`;

const step1 = { nome: 'A B', email: 'a@b.com', telefone: '11999999999', turma: 'T1', documento_nf: '12345678901' };
const fullEligible = {
  token: TOKEN,
  ...step1,
  interesse: 'sim',
  espaco_instrucao: 'casa',
  nivel: 'ouro',
  faturamento_declarado: 50000,
  proof_url: proof,
  declaracao_url: decl,
  cep: '01001000',
  logradouro: 'Rua X',
  numero: '10',
  bairro: 'Centro',
  cidade: 'SP',
  estado_uf: 'SP',
  pais: 'Brasil',
};

describe('form-progress — eligibilidade e URL de documento', () => {
  it('isPlateEligible só para ouro+', () => {
    expect(isPlateEligible('ouro')).toBe(true);
    expect(isPlateEligible('profissional')).toBe(false);
    expect(isPlateEligible(null)).toBe(false);
  });
  it('isTokenDocumentUrl exige bucket/token/https/supabase', () => {
    expect(isTokenDocumentUrl(proof, TOKEN)).toBe(true);
    expect(isTokenDocumentUrl(proof, 'outro-token')).toBe(false);
    expect(isTokenDocumentUrl('http://x.supabase.co/storage/v1/object/public/documentos/placas/' + TOKEN + '/a.pdf', TOKEN)).toBe(false);
    expect(isTokenDocumentUrl('https://evil.com/x', TOKEN)).toBe(false);
  });
});

describe('form-progress — validação progressiva', () => {
  it('step 1 exige campos básicos', () => {
    expect(validateFormProgress({ step_index: 1, nivel: 'ouro' })?.code).toBe('missing_step1_field');
    expect(validateFormProgress({ token: TOKEN, step_index: 1, nivel: 'ouro', ...step1 })).toBeNull();
  });

  it('step 3 eligible exige faturamento', () => {
    const e = validateFormProgress({ token: TOKEN, step_index: 3, nivel: 'ouro', ...step1, interesse: 'x', espaco_instrucao: 'casa' });
    expect(e?.code).toBe('missing_faturamento');
  });

  it('não-eligible não passa de step 3 nem envia', () => {
    const base = { token: TOKEN, ...step1, interesse: 'x', espaco_instrucao: 'casa', nivel: 'profissional' };
    expect(validateFormProgress({ ...base, step_index: 4 })?.code).toBe('invalid_non_eligible_progress');
    expect(validateFormProgress({ ...base, step_index: 3, status: 'enviado' })?.code).toBe('invalid_non_eligible_progress');
    expect(validateFormProgress({ ...base, step_index: 3, status: 'cadastro_concluido' })).toBeNull();
    expect(validateFormProgress({ ...base, step_index: 2, status: 'cadastro_concluido' })?.code).toBe('invalid_cadastro_status');
  });

  it('eligible não pode ser cadastro_concluido', () => {
    expect(
      validateFormProgress({ token: TOKEN, step_index: 3, nivel: 'ouro', faturamento_declarado: 50000, ...step1, interesse: 'x', espaco_instrucao: 'casa', status: 'cadastro_concluido' })?.code,
    ).toBe('invalid_eligible_status');
  });

  it('step 4/5 exigem documentos válidos do token', () => {
    const base = { token: TOKEN, ...step1, interesse: 'x', espaco_instrucao: 'casa', nivel: 'ouro', faturamento_declarado: 50000 };
    expect(validateFormProgress({ ...base, step_index: 4 })?.code).toBe('missing_proof');
    expect(validateFormProgress({ ...base, step_index: 4, proof_url: 'https://evil.com/a.pdf' })?.code).toBe('invalid_proof_url');
    expect(validateFormProgress({ ...base, step_index: 5, proof_url: proof })?.code).toBe('missing_declaracao');
  });

  it('submit completo (enviado/step 6) é válido', () => {
    expect(validateFormProgress({ ...fullEligible, step_index: 6, status: 'enviado' })).toBeNull();
    expect(validateFormProgress({ ...fullEligible, step_index: 5, status: 'enviado' })?.code).toBe('invalid_submit_step');
    expect(validateFormProgress({ ...fullEligible, step_index: 6, status: 'enviado', cep: '' })?.code).toBe('missing_address');
  });
});

describe('form-progress — coerência nível × faturamento declarado', () => {
  it('bloqueia faturamento abaixo do mínimo do nível (ex.: Diamante com 200k)', () => {
    expect(faturamentoBlockReason('diamante', 200_000)).toBe('abaixo_minimo');
    expect(faturamentoBlockReason('ouro', 49_999)).toBe('abaixo_minimo');
    expect(faturamentoBlockReason('platina', 499_999)).toBe('abaixo_minimo');
    expect(faturamentoBlockReason('diamante_vermelho', 1_000_000)).toBe('abaixo_minimo');
  });

  it('aceita valores na faixa do nível', () => {
    expect(faturamentoBlockReason('ouro', 50_000)).toBeNull();
    expect(faturamentoBlockReason('diamante', 1_500_000)).toBeNull();
    expect(faturamentoBlockReason('diamante_vermelho', 5_000_000)).toBeNull();
  });

  it('bloqueia valor absurdo (provável erro de digitação) e ignora nível não-elegível', () => {
    expect(faturamentoBlockReason('ouro', 2_000_000_000)).toBe('acima_teto');
    expect(faturamentoBlockReason('iniciante', 10)).toBeNull();
  });

  it('nivelSugeridoPorFaturamento aponta o maior nível alcançado', () => {
    expect(nivelSugeridoPorFaturamento(200_000)).toBe('ouro');
    expect(nivelSugeridoPorFaturamento(1_200_000)).toBe('diamante');
    expect(nivelSugeridoPorFaturamento(10_000_000)).toBe('diamante_vermelho');
    expect(nivelSugeridoPorFaturamento(10_000)).toBeNull();
  });

  it('validateFormProgress devolve faturamento_abaixo_nivel no step 3 (também no servidor)', () => {
    const e = validateFormProgress({ ...fullEligible, nivel: 'diamante', faturamento_declarado: 200_000, step_index: 3, status: 'rascunho' });
    expect(e).toEqual({ code: 'faturamento_abaixo_nivel', field: 'diamante' });
    expect(validateFormProgress({ ...fullEligible, step_index: 3, status: 'rascunho' })).toBeNull();
  });
});

describe('form-progress — refazer processo (bloqueio de nível por piso)', () => {
  it('sem piso não bloqueia nada', () => {
    expect(nivelRefazerBlockReason('ouro', null)).toBeNull();
    expect(nivelRefazerBlockReason('ouro', '')).toBeNull();
    expect(nivelRefazerBlockReason('platina', 'xpto')).toBeNull(); // piso desconhecido
  });

  it('piso ELEGÍVEL (placa concluída): bloqueia igual/inferior e descida p/ sem placa', () => {
    expect(nivelRefazerBlockReason('ouro', 'ouro')).toBe('nao_superior'); // mesmo nível
    expect(nivelRefazerBlockReason('ouro', 'platina')).toBe('nao_superior'); // inferior
    expect(nivelRefazerBlockReason('platina', 'diamante')).toBe('nao_superior');
    expect(nivelRefazerBlockReason('profissional', 'ouro')).toBe('nao_elegivel'); // não desce p/ cadastro
    expect(nivelRefazerBlockReason('iniciante', 'platina')).toBe('nao_elegivel');
  });

  it('piso ABAIXO de Ouro (cadastro): bloqueia igual/inferior, aceita superior mesmo sem placa', () => {
    // Piso não-elegível NÃO exige subir para Ouro — qualquer nível superior vale.
    expect(nivelRefazerBlockReason('em_formacao', 'iniciante')).toBeNull(); // sobe dentro do < Ouro
    expect(nivelRefazerBlockReason('ouro', 'profissional')).toBeNull(); // sobe para a placa
    expect(nivelRefazerBlockReason('profissional', 'profissional')).toBe('nao_superior'); // mesmo nível
    expect(nivelRefazerBlockReason('iniciante', 'profissional')).toBe('nao_superior'); // inferior
    expect(nivelRefazerBlockReason('iniciante', 'em_formacao')).toBe('nao_superior'); // inferior na escala completa
  });

  it('permite qualquer nível estritamente superior (piso elegível)', () => {
    expect(nivelRefazerBlockReason('platina', 'ouro')).toBeNull();
    expect(nivelRefazerBlockReason('diamante', 'ouro')).toBeNull();
    expect(nivelRefazerBlockReason('diamante_vermelho', 'diamante')).toBeNull();
  });

  it('piso no nível máximo bloqueia todos (nada é superior a Diamante Vermelho)', () => {
    for (const n of ['ouro', 'platina', 'diamante', 'diamante_vermelho']) {
      expect(nivelRefazerBlockReason(n, 'diamante_vermelho')).toBe('nao_superior');
    }
  });

  it('validateFormProgress aplica o piso no step 3 (servidor)', () => {
    const base = { ...fullEligible, step_index: 3, status: 'rascunho' };
    // Concluiu Ouro → tentar Ouro de novo é bloqueado
    expect(validateFormProgress({ ...base, nivel: 'ouro', nivel_anterior: 'ouro' })?.code).toBe('refazer_nivel_nao_superior');
    // Concluiu Ouro → descer para Profissional (sem placa) é bloqueado
    expect(validateFormProgress({ ...base, nivel: 'profissional', nivel_anterior: 'ouro' })?.code).toBe('refazer_nivel_nao_elegivel');
    // Concluiu Ouro → subir para Platina passa (com faturamento coerente)
    expect(validateFormProgress({ ...base, nivel: 'platina', faturamento_declarado: 500_000, nivel_anterior: 'ouro' })).toBeNull();
    // Cadastro Iniciante → subir para Em Formação (ainda < Ouro) passa (cadastro_concluido, step 3)
    expect(validateFormProgress({ token: TOKEN, ...step1, interesse: 'x', espaco_instrucao: 'casa', step_index: 3, status: 'cadastro_concluido', nivel: 'em_formacao', nivel_anterior: 'iniciante' })).toBeNull();
    // Cadastro Profissional → tentar Iniciante (inferior) é bloqueado
    expect(validateFormProgress({ token: TOKEN, ...step1, interesse: 'x', espaco_instrucao: 'casa', step_index: 3, status: 'cadastro_concluido', nivel: 'iniciante', nivel_anterior: 'profissional' })?.code).toBe('refazer_nivel_nao_superior');
  });
});
