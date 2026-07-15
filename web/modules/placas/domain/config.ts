// Domínio puro — CONFIGURAÇÕES personalizáveis do fluxo de Placas.
// Editáveis pelo admin (sem dev) e persistidas em thb_placas_config (key/value jsonb).
// Este arquivo só define formas, defaults e merges — sem acesso a Supabase.

import { AUDIT_STEPS, type AuditStep } from './auditoria';

export const PLACAS_CONFIG_KEYS = ['audit_steps', 'email_templates', 'nivel_faixas', 'form_textos'] as const;
export type PlacasConfigKey = (typeof PLACAS_CONFIG_KEYS)[number];

// ── Etapas da auditoria (override só de textos; chaves/lógica permanecem fixas) ──
export interface AuditStepOverride {
  name?: string;
  desc?: string;
  actionLabel?: string;
}

/** Aplica os overrides sobre AUDIT_STEPS, mantendo defaults quando vazio. */
export function resolveAuditSteps(overrides?: AuditStepOverride[] | null): AuditStep[] {
  return AUDIT_STEPS.map((s, i) => {
    const o = overrides?.[i];
    if (!o) return { ...s };
    const name = o.name?.trim();
    const desc = o.desc?.trim();
    const actionLabel = o.actionLabel?.trim();
    return {
      ...s,
      name: name || s.name,
      desc: desc || s.desc,
      actionLabel: actionLabel || s.actionLabel,
      shortLabel: name || s.shortLabel,
    };
  });
}

/** Converte etapas efetivas para a forma editável (usada no formulário de config). */
export function auditStepsToEditable(steps: readonly AuditStep[]): AuditStepOverride[] {
  return steps.map((s) => ({ name: s.name, desc: s.desc, actionLabel: s.actionLabel }));
}

// ── E-mails automáticos (override de assunto/introdução/corpo) ──
export interface EmailTemplateOverride {
  assunto?: string;
  introducao?: string;
  corpo_extra?: string;
}
export type EmailTemplatesConfig = Record<string, EmailTemplateOverride>;

/** Tipos de e-mail expostos na tela de configuração (label amigável). */
export const EMAIL_TIPOS_CONFIG: { tipo: string; label: string; descricao: string }[] = [
  { tipo: 'link_acesso', label: 'Link de acesso (rascunho)', descricao: 'Enviado ao concluir a 1ª etapa: link pessoal para continuar de qualquer dispositivo.' },
  { tipo: 'solicitacao_recebida', label: 'Solicitação recebida', descricao: 'Confirmação automática ao enviar o formulário (protocolo de recebimento).' },
  { tipo: 'docs_aprovados', label: 'Documentação aprovada', descricao: 'Enviado quando a documentação é validada e o aluno pode agendar a entrevista.' },
  { tipo: 'entrevista_agendada', label: 'Entrevista agendada', descricao: 'Confirmação com o link de acesso à sala.' },
  { tipo: 'entrevista_finalizada', label: 'Entrevista realizada', descricao: 'Confirma que a entrevista foi registrada.' },
  { tipo: 'placa_em_caminho', label: 'Placa a caminho', descricao: 'Enviado com o código de rastreio quando a placa é postada.' },
  { tipo: 'placa_recebida', label: 'Placa recebida (conclusão)', descricao: 'Enviado quando o admin confirma o recebimento da placa e encerra o processo.' },
  { tipo: 'lembrete_entrevista', label: 'Lembrete de entrevista (4h)', descricao: 'Enviado automaticamente ~4h antes da entrevista agendada (cron).' },
  { tipo: 'retorno_auditoria', label: 'Pedido de correção', descricao: 'Enviado quando o admin devolve a solicitação para ajustes.' },
  { tipo: 'nao_compareceu', label: 'Não compareceu', descricao: 'Enviado quando o aluno falta à entrevista e precisa reagendar.' },
  { tipo: 'nivel_registrado', label: 'Cadastro concluído (sem placa)', descricao: 'Fecho do fluxo curto: nível abaixo de Ouro registrado, sem emissão de placa.' },
  { tipo: 'solicitacao_rejeitada', label: 'Solicitação rejeitada', descricao: 'Enviado quando o admin rejeita definitivamente a solicitação.' },
];

// ── Faixas de faturamento por nível (exibidas no formulário público) ──
export interface NivelFaixa {
  nm: string;
  fx: string;
}

export const NIVEL_FAIXA_ORDER = [
  'iniciante',
  'em_formacao',
  'pessoal',
  'profissional',
  'ouro',
  'platina',
  'diamante',
  'diamante_vermelho',
] as const;

export const NIVEL_FAIXA_ICONS: Record<string, string> = {
  iniciante: 'sprout',
  em_formacao: 'biblioteca',
  pessoal: 'user',
  profissional: 'briefcase',
  ouro: 'medal',
  platina: 'coins',
  diamante: 'gem',
  diamante_vermelho: 'gem',
};

export const DEFAULT_NIVEL_FAIXAS: Record<string, NivelFaixa> = {
  iniciante: { nm: 'Iniciante', fx: 'Ainda não comecei' },
  em_formacao: { nm: 'Em Formação', fx: 'Estudando o curso' },
  pessoal: { nm: 'Pessoal', fx: 'Só minha holding' },
  profissional: { nm: 'Profissional', fx: 'Oferecendo a clientes' },
  ouro: { nm: 'Ouro', fx: 'Primeiros R$ 50k faturado' },
  platina: { nm: 'Platina', fx: 'R$ 500k em 12 meses' },
  diamante: { nm: 'Diamante', fx: 'R$ 1M em 12 meses' },
  diamante_vermelho: { nm: 'Diamante Vermelho', fx: 'R$ 5M em 12 meses' },
};

/** Faixas efetivas: default por nível, sobrescrito pelo override (nm/fx). */
export function resolveNivelFaixas(overrides?: Record<string, Partial<NivelFaixa>> | null): { v: string; ic: string; nm: string; fx: string }[] {
  return NIVEL_FAIXA_ORDER.map((v) => {
    const base = DEFAULT_NIVEL_FAIXAS[v];
    const o = overrides?.[v];
    return {
      v,
      ic: NIVEL_FAIXA_ICONS[v] || 'medal',
      nm: o?.nm?.trim() || base.nm,
      fx: o?.fx?.trim() || base.fx,
    };
  });
}

// ── Textos do formulário público ──
export interface EspacoOption {
  v: string;
  l: string;
}
export interface FormTextos {
  upload_info?: string;
  cadastro_info?: string;
  espacos?: EspacoOption[];
}

export const DEFAULT_ESPACOS: EspacoOption[] = [
  { v: 'holding_masters', l: 'Holding Masters' },
  { v: 'aurum', l: 'Mentoria Aurum' },
  { v: 'coach_platina', l: 'Coach Platina' },
  { v: 'mastermind', l: 'Diamante' },
];

export const DEFAULT_FORM_TEXTOS: Required<FormTextos> = {
  upload_info:
    'Faça o upload de um PDF/imagem com contratos, notas fiscais ou extratos que comprovem seu faturamento com Holding Familiar.',
  cadastro_info:
    'Para o seu nível, registramos apenas o cadastro — a placa fica disponível ao atingir um nível elegível.',
  espacos: DEFAULT_ESPACOS,
};

/** Textos efetivos do formulário: default sobrescrito pelo override. */
export function resolveFormTextos(overrides?: FormTextos | null): Required<FormTextos> {
  const espacos = overrides?.espacos?.filter((e) => e?.v && e?.l);
  return {
    upload_info: overrides?.upload_info?.trim() || DEFAULT_FORM_TEXTOS.upload_info,
    cadastro_info: overrides?.cadastro_info?.trim() || DEFAULT_FORM_TEXTOS.cadastro_info,
    espacos: espacos && espacos.length ? espacos : DEFAULT_ESPACOS,
  };
}

// ── Bundle completo lido do banco (value jsonb por key) ──
export interface PlacasConfig {
  audit_steps: AuditStepOverride[] | null;
  email_templates: EmailTemplatesConfig;
  nivel_faixas: Record<string, Partial<NivelFaixa>>;
  form_textos: FormTextos;
}

/** Normaliza o mapa key→value cru vindo do banco para PlacasConfig. */
export function parsePlacasConfig(raw: Record<string, unknown> | null | undefined): PlacasConfig {
  const r = raw || {};
  return {
    audit_steps: Array.isArray(r.audit_steps) ? (r.audit_steps as AuditStepOverride[]) : null,
    email_templates: (r.email_templates as EmailTemplatesConfig) || {},
    nivel_faixas: (r.nivel_faixas as Record<string, Partial<NivelFaixa>>) || {},
    form_textos: (r.form_textos as FormTextos) || {},
  };
}
