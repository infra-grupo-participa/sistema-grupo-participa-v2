'use client';

import { useState } from 'react';
import { type Aluno360, ESPACO_LABEL, SITUACAO, STATUS_ACESSO, SUGESTOES } from '../domain/aluno-360';
import { nivelOptions } from '@/shared/domain/nivel-resultado';
import { createAluno, updateAluno, type Turma } from './alunos-data';
import { SectionCard, Button } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { SecTitle, SubTitle } from './alunos-ui-bits';

const FIELD_CLS = 'mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-sm text-[var(--fg)] transition-colors focus:border-[var(--border-accent)] focus:outline-none';

// Campos de texto livre persistidos como string (null se vazio).
const TXT_FIELDS = [
  'nome', 'email', 'telefone', 'telefone_profissional', 'tipo_documento', 'profissao',
  'link_facebook', 'instagram_url', 'youtube_url', 'site_profissional',
  'cep', 'endereco_logradouro', 'endereco_numero', 'endereco_complemento', 'bairro', 'cidade', 'pais',
  'nivel_resultado', 'espaco_instrucao', 'placa_aurum', 'hotmart_ucode',
  'produto', 'oferta', 'tipo_oferta', 'origem_acesso', 'instrucao', 'regra_acesso', 'tempo_acesso',
  'status_acesso', 'status_acesso_central', 'situacao_acesso',
  'situacao_financeira', 'status_pagamento',
  'tratamento_manual', 'obs_central',
];

/** Estado inicial: ficha existente (edição) ou em branco (cadastro manual). */
function initState(a: Aluno360 | null): Record<string, string> {
  const init: Record<string, string> = {};
  const raw = (a ?? {}) as unknown as Record<string, unknown>;
  for (const k of TXT_FIELDS) init[k] = raw[k] != null ? String(raw[k]) : '';
  if (!a) init.pais = 'Brasil'; // default da coluna
  init.documento = a?.documento && !a.documento.includes('*') ? a.documento : '';
  init.estado = a?.estado || '';
  init.turma_id = a?.turma_id ? String(a.turma_id) : '';
  init.turma_aurum_id = a?.turma_aurum_id ? String(a.turma_aurum_id) : '';
  init.eh_socio = a?.eh_socio ? 'sim' : 'nao';
  init.data_expiracao = a?.data_expiracao || '';
  init.ultimo_pagamento = a?.ultimo_pagamento || '';
  init.mes_expiracao = a?.mes_expiracao != null ? String(a.mes_expiracao) : '';
  init.ano_expiracao = a?.ano_expiracao != null ? String(a.ano_expiracao) : '';
  init.valor_total = a?.valor_total != null ? String(a.valor_total) : '';
  init.valor_pago = a?.valor_pago != null ? String(a.valor_pago) : '';
  init.saldo_devedor = a?.saldo_devedor != null ? String(a.saldo_devedor) : '';
  init.num_cobrancas = a?.num_cobrancas != null ? String(a.num_cobrancas) : '';
  return init;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/**
 * Ficha do aluno em modo escrita. `a = null` cadastra um novo registro em thb_alunos;
 * com `a` preenchido, edita o existente (porta de saveAlunoEdit).
 */
export function AlunoForm({ a, turmas, onSaved, emailJaCadastrado }: {
  a: Aluno360 | null;
  turmas: Turma[];
  /** No cadastro, `novoId` traz o id gerado para abrir a ficha em seguida. */
  onSaved: (msg: string, novoId?: string) => void;
  /** Só no cadastro: devolve o nome do aluno que já ocupa o e-mail (UNIQUE no banco). */
  emailJaCadastrado?: (email: string) => string | null;
}) {
  const criando = a === null;
  const [f, setF] = useState<Record<string, string>>(() => initState(a));
  const [busy, setBusy] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const s = (k: string, v: string) => setF((p) => ({ ...p, [k]: v }));
  const thbTurmas = turmas.filter((t) => t.tipo !== 'aurum');
  const aurumTurmas = turmas.filter((t) => t.tipo === 'aurum');

  const emailTrim = f.email.trim();
  const duplicado = criando && emailTrim ? emailJaCadastrado?.(emailTrim) ?? null : null;
  const emailInvalido = Boolean(emailTrim) && !EMAIL_RE.test(emailTrim);
  const bloqueado = criando && (!f.nome.trim() || Boolean(duplicado) || emailInvalido);

  async function save() {
    setErro(null);
    if (criando && !f.nome.trim()) { setErro('Informe o nome do aluno.'); return; }
    if (emailInvalido) { setErro('E-mail inválido.'); return; }

    setBusy(true);
    const fields: Record<string, unknown> = {};
    const txt = (k: string) => (f[k]?.trim() ? f[k].trim() : null);
    const numv = (k: string) => { const t = f[k]?.trim(); if (!t) return null; const n = Number(t.replace(',', '.')); return Number.isFinite(n) ? n : null; };
    const intv = (k: string) => { const n = numv(k); return n == null ? null : Math.trunc(n); };
    const dt = (k: string) => (f[k]?.trim() ? f[k].trim() : null);

    for (const k of TXT_FIELDS) fields[k] = txt(k);
    fields.estado = f.estado?.trim() ? f.estado.trim().toUpperCase() : null;
    if (f.documento.trim()) fields.documento = f.documento.trim(); // só sobrescreve se preenchido (mascarado fica vazio)
    fields.turma_id = f.turma_id ? Number(f.turma_id) : null;
    fields.turma_aurum_id = f.turma_aurum_id ? Number(f.turma_aurum_id) : null;
    fields.eh_socio = f.eh_socio === 'sim';
    fields.data_expiracao = dt('data_expiracao');
    fields.ultimo_pagamento = dt('ultimo_pagamento');
    fields.mes_expiracao = intv('mes_expiracao');
    fields.ano_expiracao = intv('ano_expiracao');
    fields.valor_total = numv('valor_total');
    fields.valor_pago = numv('valor_pago');
    fields.saldo_devedor = numv('saldo_devedor');
    fields.num_cobrancas = intv('num_cobrancas');

    if (criando) {
      const r = await createAluno(fields);
      setBusy(false);
      if (!r.ok) { setErro(r.msg || 'Erro ao cadastrar.'); return; }
      onSaved('Aluno cadastrado!', r.id);
      return;
    }

    const r = await updateAluno(a.id, fields);
    setBusy(false);
    if (!r.ok) { setErro('Erro ao salvar: ' + (r.msg || '')); return; }
    onSaved('Aluno atualizado!');
  }

  // Funções (não componentes) — evitam recriar tipo de componente a cada render (perda de foco).
  const inp = (k: string, label: string, type = 'text') => (
    <label className="block"><span className="text-xs text-[var(--fg-3)]">{label}</span>
      <input type={type} value={f[k]} onChange={(e) => s(k, e.target.value)} className={FIELD_CLS} /></label>
  );
  const inpList = (k: string, label: string, opts: readonly string[]) => (
    <label className="block"><span className="text-xs text-[var(--fg-3)]">{label}</span>
      <input list={`dl-${k}`} value={f[k]} onChange={(e) => s(k, e.target.value)} className={FIELD_CLS} />
      <datalist id={`dl-${k}`}>{opts.map((o) => <option key={o} value={o} />)}</datalist></label>
  );
  const sel = (k: string, label: string, opts: { value: string; label: string }[], comVazio = true) => (
    <label className="block"><span className="text-xs text-[var(--fg-3)]">{label}</span>
      <select value={f[k]} onChange={(e) => s(k, e.target.value)} className={FIELD_CLS}>
        {comVazio && <option value="">—</option>}{opts.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select></label>
  );
  const espacoOpts = Object.entries(ESPACO_LABEL).map(([value, label]) => ({ value, label }));
  const situacaoOpts = Object.entries(SITUACAO).map(([value, x]) => ({ value, label: x.label }));
  const statusAcessoOpts = Object.entries(STATUS_ACESSO).map(([value, x]) => ({ value, label: x.label }));

  // Edição espelha a MESMA ordem/agrupamento da leitura (Faturamento → Dados → Acesso → Observações).
  const grid = 'grid grid-cols-1 sm:grid-cols-2 gap-2.5';
  return (
    <div className="space-y-4">
      <SectionCard title={<SecTitle icon="user">Dados Pessoais</SecTitle>}>
        <div className={grid}>
          {inp('nome', criando ? 'Nome *' : 'Nome')}
          {inp('email', 'E-mail')}
          {inp('telefone', 'Telefone')}
          {inp('telefone_profissional', 'Tel. profissional')}
          {inp('documento', criando ? 'Documento' : 'Documento (vazio mantém)')}
          {inp('tipo_documento', 'Tipo de documento')}
          {inp('profissao', 'Profissão')}
        </div>
        {duplicado && (
          <div className="mt-2 p-2 rounded-[var(--r-md)] bg-[var(--red-subtle)] text-[var(--red)] text-xs flex items-center gap-1.5">
            <Icon name="alert" size={13} /> E-mail já usado por <strong>{duplicado}</strong>. Edite a ficha existente em vez de duplicar.
          </div>
        )}
        {emailInvalido && !duplicado && (
          <div className="mt-2 text-xs text-[var(--red)]">E-mail inválido.</div>
        )}
        <SubTitle>Endereço</SubTitle>
        <div className={grid}>
          {inp('cep', 'CEP')}
          {inp('endereco_logradouro', 'Logradouro')}
          {inp('endereco_numero', 'Número')}
          {inp('endereco_complemento', 'Complemento')}
          {inp('bairro', 'Bairro')}
          {inp('cidade', 'Cidade')}
          {inp('estado', 'Estado (UF)')}
          {inp('pais', 'País')}
        </div>
        <SubTitle>Presença online</SubTitle>
        <div className={grid}>
          {inp('link_facebook', 'Facebook')}
          {inp('instagram_url', 'Instagram')}
          {inp('youtube_url', 'YouTube')}
          {inp('site_profissional', 'Site')}
        </div>
      </SectionCard>

      <SectionCard title={<SecTitle icon="graduation">Acesso ao Curso</SecTitle>}>
        <SubTitle>Produto &amp; oferta</SubTitle>
        <div className={grid}>
          {inpList('produto', 'Produto', SUGESTOES.produto)}
          {inp('oferta', 'Oferta')}
          {inpList('tipo_oferta', 'Tipo de oferta', SUGESTOES.tipo_oferta)}
          {inpList('origem_acesso', 'Origem de acesso', SUGESTOES.origem_acesso)}
          {inpList('instrucao', 'Instrução', SUGESTOES.instrucao)}
          {sel('espaco_instrucao', 'Espaço de instrução', espacoOpts)}
        </div>
        <SubTitle>Programa</SubTitle>
        <div className={grid}>
          {sel('nivel_resultado', 'Nível de resultado', nivelOptions().map((n) => ({ value: n.id, label: n.label })))}
          {sel('eh_socio', 'Papel', [{ value: 'nao', label: 'Titular' }, { value: 'sim', label: 'Sócio' }], false)}
          {inp('placa_aurum', 'Placa Aurum')}
          {sel('turma_id', 'Turma THB', thbTurmas.map((t) => ({ value: String(t.id), label: t.codigo })))}
          {sel('turma_aurum_id', 'Turma Aurum', aurumTurmas.map((t) => ({ value: String(t.id), label: t.codigo })))}
        </div>
        <SubTitle>Vigência</SubTitle>
        <div className={grid}>
          {inpList('regra_acesso', 'Regra de acesso', SUGESTOES.regra_acesso)}
          {inpList('tempo_acesso', 'Tempo de acesso', SUGESTOES.tempo_acesso)}
          {inp('data_expiracao', 'Vencimento', 'date')}
          {inp('mes_expiracao', 'Mês expiração', 'number')}
          {inp('ano_expiracao', 'Ano expiração', 'number')}
        </div>
        <SubTitle>Hotmart &amp; status</SubTitle>
        <div className={grid}>
          {inp('hotmart_ucode', 'Hotmart UCode')}
          {sel('status_acesso', 'Status de acesso', statusAcessoOpts)}
          {inpList('status_acesso_central', 'Status central', SUGESTOES.status_acesso_central)}
          {sel('situacao_acesso', 'Situação de acesso', situacaoOpts)}
        </div>
      </SectionCard>

      <SectionCard title={<SecTitle icon="pencil">Observações</SecTitle>}>
        <div className="space-y-2.5">
          {inp('tratamento_manual', 'Tratamento manual')}
          <label className="block"><span className="text-xs text-[var(--fg-3)]">Obs central</span>
            <textarea value={f.obs_central} onChange={(e) => s('obs_central', e.target.value)} rows={3} className={FIELD_CLS} /></label>
        </div>
      </SectionCard>

      {erro && <div className="p-2.5 rounded-[var(--r-md)] bg-[var(--red-subtle)] text-[var(--red)] text-xs">{erro}</div>}

      <Button onClick={save} disabled={busy || bloqueado} className="w-full justify-center py-2.5">
        <Icon name="check" size={15} /> {busy ? 'Salvando…' : criando ? 'Cadastrar aluno' : 'Salvar alterações'}
      </Button>
    </div>
  );
}
