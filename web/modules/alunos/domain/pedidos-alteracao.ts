// Domínio puro dos Pedidos de alteração de cadastro (migration 20261005j_pedidos_alteracao.sql).
// Quem pede não tem acesso à Central: vê só os próprios pedidos. Quem aprova (pa_aprovadores no banco)
// decide na aba da Central. As regras aqui ESPELHAM as do banco (pa_normalizar, pa_pode_pedir); a trava
// real é a do Postgres, a da tela só evita mandar pedido que o banco vai recusar.
import type { GpUser } from '@/shared/domain/auth';
import { ESPACO_LABEL, INSTRUCOES, parseInstrucao } from './aluno-360';

export const SETOR_PEDIDOS = 'pedidos_alteracao';

/** Espelho de pa_pode_pedir(): dev/admin, ou gestor/operador com a área 'pedidos_alteracao' (catálogo 3.6). */
export function podePedirAlteracao(u: GpUser | null): boolean {
  if (!u) return false;
  if (u.cargo === 'dev' || u.cargo === 'admin') return true;
  if (u.cargo === 'gestor' || u.cargo === 'operador') return (u.setores || []).includes(SETOR_PEDIDOS);
  return false;
}

export type TipoPedido = 'alterar_dado' | 'trocar_socio' | 'outro';
export type StatusPedido = 'pendente' | 'aprovado' | 'recusado' | 'aplicado' | 'erro';
export type StatusPlanilha = 'pendente' | 'ok' | 'erro';

export const ROTULO_TIPO: Record<TipoPedido, string> = {
  alterar_dado: 'Alterar dado',
  trocar_socio: 'Trocar sócio',
  outro: 'Outro',
};

export const ROTULO_STATUS: Record<StatusPedido, string> = {
  pendente: 'Aguardando aprovação',
  aprovado: 'Aprovado, falta aplicar',
  recusado: 'Recusado',
  aplicado: 'Aplicado',
  erro: 'Erro ao aplicar',
};

export const TOM_STATUS: Record<StatusPedido, 'warning' | 'info' | 'danger' | 'success'> = {
  pendente: 'warning',
  aprovado: 'info',
  recusado: 'danger',
  aplicado: 'success',
  erro: 'danger',
};

export const ROTULO_PLANILHA: Record<StatusPlanilha, string> = {
  pendente: 'Planilha: pendente',
  ok: 'Planilha: atualizada',
  erro: 'Planilha: erro',
};

/**
 * Lista FECHADA de campos editáveis por "alterar dado". Mesma ordem e chaves de pa_campos() no banco
 * (o teste confere contra a migration). Nunca dinheiro, compra ou Hotmart.
 */
export const CAMPOS_EDITAVEIS = [
  { campo: 'nome', rotulo: 'Nome' },
  { campo: 'email', rotulo: 'E-mail' },
  { campo: 'telefone', rotulo: 'Telefone' },
  { campo: 'telefone_profissional', rotulo: 'Telefone profissional' },
  { campo: 'documento', rotulo: 'Documento (CPF ou CNPJ)' },
  { campo: 'endereco', rotulo: 'Endereço' },
  { campo: 'profissao', rotulo: 'Profissão' },
  { campo: 'turma_id', rotulo: 'Turma' },
  { campo: 'instrucao', rotulo: 'Instrução' },
  { campo: 'espaco_instrucao', rotulo: 'Espaço de instrução' },
  { campo: 'obs_central', rotulo: 'Observação da Central' },
] as const;
export type CampoEditavel = (typeof CAMPOS_EDITAVEIS)[number]['campo'];

export const rotuloCampo = (campo: string | null | undefined): string =>
  CAMPOS_EDITAVEIS.find((c) => c.campo === campo)?.rotulo ?? (campo || '');

/** Partes do endereço, na ordem de pa_colunas_endereco(). */
export const ENDERECO_PARTES = [
  { k: 'cep', rotulo: 'CEP' },
  { k: 'endereco_logradouro', rotulo: 'Logradouro' },
  { k: 'endereco_numero', rotulo: 'Número' },
  { k: 'endereco_complemento', rotulo: 'Complemento' },
  { k: 'bairro', rotulo: 'Bairro' },
  { k: 'cidade', rotulo: 'Cidade' },
  { k: 'estado', rotulo: 'Estado (UF)' },
  { k: 'pais', rotulo: 'País' },
] as const;
export type Endereco = Partial<Record<(typeof ENDERECO_PARTES)[number]['k'], string | null>>;

export const ESPACOS = Object.keys(ESPACO_LABEL);
export { INSTRUCOES };

export type Validacao = { ok: true; valor: unknown } | { ok: false; erro: string };

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const digitos = (v: unknown) => String(v ?? '').replace(/\D/g, '');
const txt = (v: unknown): string | null => {
  const s = String(v ?? '').trim();
  return s ? s : null;
};

/** Telefone no padrão da Central (55 + DDD + número). Espelho de pa_telefone(). */
export function normalizarTelefone(v: unknown): Validacao {
  let d = digitos(v);
  if (!d) return { ok: true, valor: null };
  if (d.length === 10 || d.length === 11) d = '55' + d;
  if (d.length < 10 || d.length > 15) return { ok: false, erro: 'Telefone inválido: use DDD + número (ex.: 21 99999-9999).' };
  return { ok: true, valor: d };
}

/** Valida e normaliza o valor pedido. Espelho de pa_normalizar() (mesmas mensagens). */
export function validarValor(campo: string, valor: unknown): Validacao {
  if (!CAMPOS_EDITAVEIS.some((c) => c.campo === campo)) return { ok: false, erro: 'Campo fora da lista de campos editáveis.' };
  const v = txt(valor);
  switch (campo as CampoEditavel) {
    case 'nome': {
      const n = (v ?? '').replace(/\s+/g, ' ');
      if (n.length < 3 || n.length > 200) return { ok: false, erro: 'Nome deve ter entre 3 e 200 caracteres.' };
      return { ok: true, valor: n };
    }
    case 'email':
      if (!v || !EMAIL_RE.test(v) || v.length > 200) return { ok: false, erro: 'E-mail inválido.' };
      return { ok: true, valor: v };
    case 'telefone':
    case 'telefone_profissional':
      return normalizarTelefone(v);
    case 'documento': {
      const d = digitos(v);
      if (d.length !== 11 && d.length !== 14) return { ok: false, erro: 'Documento inválido: CPF com 11 dígitos ou CNPJ com 14.' };
      return { ok: true, valor: d };
    }
    case 'endereco': {
      if (!valor || typeof valor !== 'object') return { ok: false, erro: 'Endereço inválido.' };
      const e = valor as Record<string, unknown>;
      const out: Record<string, string | null> = {};
      for (const { k } of ENDERECO_PARTES) {
        let p = txt(e[k]);
        if (p) p = p.slice(0, 200);
        if (k === 'cep' && p) {
          p = digitos(p);
          if (p.length !== 8) return { ok: false, erro: 'CEP deve ter 8 dígitos.' };
        } else if (k === 'estado' && p) {
          p = p.toUpperCase();
          if (!/^[A-Z]{2}$/.test(p)) return { ok: false, erro: 'Estado deve ser a sigla de 2 letras (ex.: SP).' };
        }
        out[k] = p;
      }
      return { ok: true, valor: out };
    }
    case 'turma_id':
      if (!v || !/^\d{1,6}$/.test(v)) return { ok: false, erro: 'Turma inexistente.' };
      return { ok: true, valor: Number(v) };
    case 'instrucao': {
      const i = (v ?? '').toUpperCase();
      if (!INSTRUCOES.includes(i)) return { ok: false, erro: 'Instrução fora das 12 da Central.' };
      return { ok: true, valor: i };
    }
    case 'espaco_instrucao':
      if (!v || !ESPACOS.includes(v)) return { ok: false, erro: 'Espaço de instrução inválido.' };
      return { ok: true, valor: v };
    case 'profissao':
      if ((v ?? '').length > 200) return { ok: false, erro: 'Profissão com mais de 200 caracteres.' };
      return { ok: true, valor: v };
    case 'obs_central':
      if ((v ?? '').length > 2000) return { ok: false, erro: 'Observação com mais de 2000 caracteres.' };
      return { ok: true, valor: v };
  }
  return { ok: false, erro: 'Campo sem regra de validação.' };
}

/** Motivo obrigatório (5 a 2000) e evidência opcional só como link. Espelho de pa_criar(). */
export function validarMotivoEvidencia(motivo: string, evidencia: string): string | null {
  const m = motivo.trim();
  if (m.length < 5) return 'Explique o motivo (mínimo 5 caracteres).';
  if (m.length > 2000) return 'Motivo com mais de 2000 caracteres.';
  const e = evidencia.trim();
  if (e && (!/^https?:\/\/\S+$/.test(e) || e.length > 1000)) return 'Evidência deve ser um link (http ou https).';
  return null;
}

// ── Troca de sócio ──

/** Resumo de aluno devolvido pela busca (pa_resumo_aluno): só o mínimo para distinguir homônimos. */
export interface AlunoResumo {
  id: string;
  nome: string | null;
  instrucao: string | null;
  espaco: string | null;
  eh_socio: boolean;
  titular_nome: string | null;
  titular_id: string | null;
  turma: string | null;
  email: string | null;
  telefone_final: string | null;
  doc_final: string | null;
  num_socios: number | null;
}

/**
 * Instrução que o sócio que entra recebe: o nível do titular com " - SÓCIO" (sócio acompanha o titular).
 * Espelho de pa_instrucao_canonica(titular, espaço, false) + sufixo. Null = titular sem instrução nem espaço.
 */
export function instrucaoDoSocio(titular: { instrucao: string | null; espaco_instrucao: string | null }): string | null {
  const i = parseInstrucao({ instrucao: titular.instrucao, espaco_instrucao: titular.espaco_instrucao, eh_socio: false });
  return i ? `${i.nivel} - SÓCIO` : null;
}

export interface SocioNovo { nome: string; email: string; telefone: string; documento: string }

/**
 * Confere a troca antes de enviar. Espelho das recusas de pa_criar() para trocar_socio.
 * `socios` = sócios atuais do titular (pa_socios_do_titular).
 */
export function validarTrocaSocio(p: {
  titular: AlunoResumo | null;
  sai: AlunoResumo | null;
  socios: AlunoResumo[];
  entra: AlunoResumo | null;
  novo: SocioNovo | null;
}): string | null {
  const { titular, sai, socios, entra, novo } = p;
  if (!titular) return 'Escolha o titular.';
  if (titular.eh_socio) return 'O aluno escolhido é sócio. Escolha o titular.';
  if (!sai) return 'Escolha o sócio que sai.';
  if (!socios.some((s) => s.id === sai.id)) return `${sai.nome} não é sócio de ${titular.nome}.`;
  if (entra) {
    if (entra.id === titular.id || entra.id === sai.id) return 'O sócio que entra tem de ser outra pessoa.';
    if (socios.some((s) => s.id === entra.id)) return `${entra.nome} já é sócio deste titular.`;
    if (entra.titular_id) return `${entra.nome} já é sócio de outro titular.`;
    return null;
  }
  if (!novo) return 'Escolha o sócio que entra (existente ou novo).';
  if (novo.nome.trim().replace(/\s+/g, ' ').length < 3) return 'Informe o nome completo do sócio novo.';
  if (!EMAIL_RE.test(novo.email.trim())) return 'Sócio novo: E-mail inválido.';
  const t = normalizarTelefone(novo.telefone);
  if (!t.ok) return 'Sócio novo: ' + t.erro;
  if (novo.documento.trim()) {
    const d = validarValor('documento', novo.documento);
    if (!d.ok) return 'Sócio novo: ' + d.erro;
  }
  return null;
}

/** Texto curto de distinção de um aluno na busca (instrução, sócio de, turma, contato parcial). */
export function distincaoAluno(a: AlunoResumo, rotuloInstrucao: (i: string) => string = (i) => i): string {
  return [
    a.instrucao ? rotuloInstrucao(a.instrucao) : null,
    a.eh_socio ? `sócio de ${a.titular_nome || 'titular sem nome'}` : null,
    a.turma ? `turma ${a.turma}` : null,
    a.email,
    a.telefone_final ? `tel. final ${a.telefone_final}` : null,
    a.doc_final ? `doc. final ${a.doc_final}` : null,
  ].filter(Boolean).join(' · ');
}

// ── Linhas de tela (pa_linha) ──

export interface EventoPedido { acao: string; em: string; por: string | null; detalhe: Record<string, unknown> }

export interface PedidoLinha {
  id: number;
  tipo: TipoPedido;
  status: StatusPedido;
  aluno_id: string | null;
  aluno_nome: string;
  aluno: AlunoResumo | null;
  campo: string | null;
  de: string | null;
  para: string | null;
  agora: string | null;
  valor_novo: unknown;
  conflito: boolean;
  socio_sai_id: string | null;
  socio_sai_nome: string | null;
  socio_sai_vinculado: boolean | null;
  socio_entra_id: string | null;
  socio_entra_nome: string | null;
  socio_entra_novo: { nome?: string; email?: string; telefone?: string | null; documento?: string | null } | null;
  descricao: string | null;
  motivo: string;
  evidencia: string | null;
  solicitado_em: string;
  solicitado_por_nome: string | null;
  decidido_em: string | null;
  decidido_por_nome: string | null;
  motivo_recusa: string | null;
  conflito_confirmado: boolean;
  aplicado_em: string | null;
  erro_msg: string | null;
  planilha_status: StatusPlanilha | null;
  planilha_em: string | null;
  planilha_erro: string | null;
  ra_caso_id: string | null;
  historico: EventoPedido[] | null;
}

export interface PapelPedidos { pode_pedir: boolean; pode_aprovar: boolean; pode_ver_doc: boolean; pendentes: number | null }

/** Resumo de uma linha em texto (lista do solicitante e cabeçalho do aprovador). */
export function resumoPedido(p: Pick<PedidoLinha, 'tipo' | 'campo' | 'de' | 'para' | 'socio_sai_nome' | 'socio_entra_nome' | 'descricao'>): string {
  if (p.tipo === 'alterar_dado') return `${rotuloCampo(p.campo)}: ${p.de ?? '(vazio)'} → ${p.para ?? '(vazio)'}`;
  if (p.tipo === 'trocar_socio') return `Sai ${p.socio_sai_nome ?? '?'}, entra ${p.socio_entra_nome ?? '?'}`;
  return p.descricao ?? '';
}

/** Ajuste do aprovador só cabe em campo de texto simples (endereço e listas se recusam e pedem de novo). */
export const campoAceitaAjusteTexto = (campo: string | null): boolean =>
  !!campo && ['nome', 'email', 'telefone', 'telefone_profissional', 'documento', 'profissao', 'obs_central'].includes(campo);
