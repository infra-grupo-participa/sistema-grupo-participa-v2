'use client';

import { useEffect, useRef, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import * as configData from './placas-config-data';
import {
  resolveAuditSteps,
  auditStepsToEditable,
  EMAIL_TIPOS_CONFIG,
  DEFAULT_NIVEL_FAIXAS,
  DEFAULT_FORM_TEXTOS,
  NIVEL_FAIXA_ORDER,
  type PlacasConfig,
  type EmailTemplateOverride,
  type NivelFaixa,
  type EspacoOption,
} from '../../domain/config';
import { defaultEmailTemplate, type EmailTipo } from '../../application/email-content';
import { Card, Button, Input } from '@/shared/ui/components';

/** Pré-preenche os campos de e-mail com os modelos padrão (legado), sobrepondo o que foi salvo. */
function seedEmails(saved: Record<string, EmailTemplateOverride> | undefined): Record<string, EmailTemplateOverride> {
  const out: Record<string, EmailTemplateOverride> = {};
  for (const t of EMAIL_TIPOS_CONFIG) {
    const d = defaultEmailTemplate(t.tipo as EmailTipo);
    const ov = saved?.[t.tipo] || {};
    out[t.tipo] = {
      assunto: ov.assunto || d.assunto,
      introducao: ov.introducao || d.introducao,
      corpo_extra: ov.corpo_extra || d.corpo_extra,
    };
  }
  return out;
}

function Area(props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const { className = '', ...rest } = props;
  return <textarea {...rest} className={`w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)] placeholder:text-[var(--fg-4)] ${className}`} />;
}

function CfgLabel({ children }: { children: React.ReactNode }) {
  return <span className="block text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-1">{children}</span>;
}

export function ConfigPanel({
  canEdit,
  cfg,
  onSaved,
  onBack,
  flash,
}: {
  canEdit: boolean;
  cfg: PlacasConfig | null;
  onSaved: (next: PlacasConfig) => void;
  onBack: () => void;
  flash: (m: string) => void;
}) {
  const base: PlacasConfig = cfg ?? { audit_steps: null, email_templates: {}, nivel_faixas: {}, form_textos: {} };

  const [sec, setSec] = useState<'emails' | 'etapas' | 'faixas' | 'form'>('emails');
  const [emails, setEmails] = useState<Record<string, EmailTemplateOverride>>(() => seedEmails(base.email_templates));
  const [etapas, setEtapas] = useState(() => auditStepsToEditable(resolveAuditSteps(base.audit_steps)));
  const [faixas, setFaixas] = useState<Record<string, NivelFaixa>>(() => {
    const m: Record<string, NivelFaixa> = {};
    for (const v of NIVEL_FAIXA_ORDER) m[v] = { ...DEFAULT_NIVEL_FAIXAS[v], ...(base.nivel_faixas?.[v] || {}) };
    return m;
  });
  const [textos, setTextos] = useState<{ upload_info: string; cadastro_info: string; espacos: EspacoOption[] }>(() => ({
    upload_info: base.form_textos?.upload_info || DEFAULT_FORM_TEXTOS.upload_info,
    cadastro_info: base.form_textos?.cadastro_info || DEFAULT_FORM_TEXTOS.cadastro_info,
    espacos: base.form_textos?.espacos?.length ? base.form_textos.espacos : DEFAULT_FORM_TEXTOS.espacos,
  }));
  const seeded = useRef(false);

  // Reseed quando a config termina de carregar (cfg null → carregado).
  useEffect(() => {
    if (!cfg || seeded.current) return;
    seeded.current = true;
    setEmails(seedEmails(cfg.email_templates));
    setEtapas(auditStepsToEditable(resolveAuditSteps(cfg.audit_steps)));
    const m: Record<string, NivelFaixa> = {};
    for (const v of NIVEL_FAIXA_ORDER) m[v] = { ...DEFAULT_NIVEL_FAIXAS[v], ...(cfg.nivel_faixas?.[v] || {}) };
    setFaixas(m);
    setTextos({
      upload_info: cfg.form_textos?.upload_info || DEFAULT_FORM_TEXTOS.upload_info,
      cadastro_info: cfg.form_textos?.cadastro_info || DEFAULT_FORM_TEXTOS.cadastro_info,
      espacos: cfg.form_textos?.espacos?.length ? cfg.form_textos.espacos : DEFAULT_FORM_TEXTOS.espacos,
    });
  }, [cfg]);

  const [busy, setBusy] = useState(false);
  async function persist(key: 'email_templates' | 'audit_steps' | 'nivel_faixas' | 'form_textos', value: unknown) {
    if (!canEdit) return;
    setBusy(true);
    const ok = await configData.savePlacasConfig(key, value);
    setBusy(false);
    if (!ok) { flash('Não foi possível salvar.'); return; }
    onSaved({ ...base, [key]: value } as PlacasConfig);
    flash('Configuração salva!');
  }

  const setEmail = (tipo: string, campo: keyof EmailTemplateOverride, v: string) =>
    setEmails((p) => ({ ...p, [tipo]: { ...p[tipo], [campo]: v } }));
  const setEtapa = (i: number, campo: 'name' | 'desc' | 'actionLabel', v: string) =>
    setEtapas((p) => p.map((e, idx) => (idx === i ? { ...e, [campo]: v } : e)));
  const setFaixa = (v: string, campo: keyof NivelFaixa, val: string) =>
    setFaixas((p) => ({ ...p, [v]: { ...p[v], [campo]: val } }));

  const SECOES: { k: typeof sec; label: string; icon: string }[] = [
    { k: 'emails', label: 'E-mails automáticos', icon: 'mail' },
    { k: 'etapas', label: 'Etapas da auditoria', icon: 'check-circle' },
    { k: 'faixas', label: 'Faixas de faturamento', icon: 'coins' },
    { k: 'form', label: 'Textos do formulário', icon: 'clipboard' },
  ];

  return (
    <div>
      <div className="flex items-start justify-between gap-3 flex-wrap mb-1">
        <h1 className="text-2xl font-bold text-[var(--fg)]">Configurações de <span className="text-[var(--accent)]">Placas</span></h1>
        <Button variant="ghost" size="sm" onClick={onBack}><Icon name="arrow-left" size={14} /> Voltar às solicitações</Button>
      </div>
      <p className="text-sm text-[var(--fg-3)] mb-4">Ajuste textos, etapas, e-mails e faixas sem depender de um desenvolvedor. Campos em branco usam o texto padrão.</p>

      {!canEdit && <div className="rounded-[var(--r-md)] bg-[var(--surface-3)] p-3 text-sm text-[var(--fg-3)] mb-4">Somente leitura — você não tem permissão para editar.</div>}

      <div className="flex gap-1 border-b border-[var(--border)] mb-4 overflow-x-auto">
        {SECOES.map((s) => (
          <button key={s.k} onClick={() => setSec(s.k)} className={`px-4 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 -mb-px transition-colors inline-flex items-center gap-2 ${sec === s.k ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)] hover:text-[var(--fg-2)]'}`}>
            <Icon name={s.icon} size={14} /> {s.label}
          </button>
        ))}
      </div>

      {sec === 'emails' && (
        <div className="space-y-4">
          <div className="rounded-[var(--r-md)] bg-[var(--surface-3)] border border-[var(--border)] p-3 text-xs text-[var(--fg-3)] leading-relaxed">
            Os campos vêm <strong className="text-[var(--fg-2)]">pré-preenchidos com os modelos atuais</strong> — edite à vontade. Blocos automáticos (caixa da entrevista, código de rastreio e motivo do retorno) são inseridos no envio, então não precisa colá-los aqui.
          </div>
          {EMAIL_TIPOS_CONFIG.map((t, i) => {
            const temBloco = t.tipo === 'entrevista_agendada' || t.tipo === 'placa_em_caminho' || t.tipo === 'retorno_auditoria';
            return (
              <Card key={t.tipo} className="p-4 gp-rise" style={{ animationDelay: `${i * 45}ms` }}>
                <div className="font-semibold text-[var(--fg)]">{t.label}</div>
                <div className="text-xs text-[var(--fg-3)] mb-3">{t.descricao}</div>
                <div className="space-y-2">
                  <div><CfgLabel>Assunto</CfgLabel><Input value={emails[t.tipo]?.assunto ?? ''} onChange={(e) => setEmail(t.tipo, 'assunto', e.target.value)} disabled={!canEdit} /></div>
                  <div><CfgLabel>Introdução</CfgLabel><Area rows={2} value={emails[t.tipo]?.introducao ?? ''} onChange={(e) => setEmail(t.tipo, 'introducao', e.target.value)} disabled={!canEdit} /></div>
                  <div>
                    <CfgLabel>Corpo (aceita HTML)</CfgLabel>
                    <Area rows={5} value={emails[t.tipo]?.corpo_extra ?? ''} onChange={(e) => setEmail(t.tipo, 'corpo_extra', e.target.value)} disabled={!canEdit} className="font-mono text-xs" />
                    {temBloco && <p className="mt-1 text-[11px] text-[var(--fg-3)]"><Icon name="check" size={11} className="inline text-[var(--green)]" /> O bloco dinâmico deste e-mail é adicionado automaticamente no topo do corpo.</p>}
                  </div>
                </div>
              </Card>
            );
          })}
          {canEdit && <Button variant="primary" disabled={busy} onClick={() => persist('email_templates', emails)}><Icon name="check" size={14} /> Salvar e-mails</Button>}
        </div>
      )}

      {sec === 'etapas' && (
        <div className="space-y-3">
          {etapas.map((e, i) => (
            <Card key={i} className="p-4 gp-rise" style={{ animationDelay: `${i * 45}ms` }}>
              <div className="text-[11px] font-bold uppercase tracking-wide text-[var(--accent)] mb-2">Etapa {i + 1}</div>
              <div className="grid sm:grid-cols-2 gap-2">
                <div><CfgLabel>Nome</CfgLabel><Input value={e.name ?? ''} onChange={(ev) => setEtapa(i, 'name', ev.target.value)} disabled={!canEdit} /></div>
                <div><CfgLabel>Rótulo do botão de avanço</CfgLabel><Input value={e.actionLabel ?? ''} onChange={(ev) => setEtapa(i, 'actionLabel', ev.target.value)} disabled={!canEdit} /></div>
                <div className="sm:col-span-2"><CfgLabel>Descrição</CfgLabel><Area rows={2} value={e.desc ?? ''} onChange={(ev) => setEtapa(i, 'desc', ev.target.value)} disabled={!canEdit} /></div>
              </div>
            </Card>
          ))}
          {canEdit && <Button variant="primary" disabled={busy} onClick={() => persist('audit_steps', etapas)}><Icon name="check" size={14} /> Salvar etapas</Button>}
        </div>
      )}

      {sec === 'faixas' && (
        <div className="space-y-3">
          <Card className="p-4">
            <div className="grid gap-2">
              {NIVEL_FAIXA_ORDER.map((v) => (
                <div key={v} className="grid sm:grid-cols-[1fr_2fr] gap-2 items-center">
                  <Input value={faixas[v]?.nm ?? ''} onChange={(e) => setFaixa(v, 'nm', e.target.value)} placeholder="Nome do nível" disabled={!canEdit} />
                  <Input value={faixas[v]?.fx ?? ''} onChange={(e) => setFaixa(v, 'fx', e.target.value)} placeholder="Faixa (ex.: R$ 500k em 12 meses)" disabled={!canEdit} />
                </div>
              ))}
            </div>
          </Card>
          {canEdit && <Button variant="primary" disabled={busy} onClick={() => persist('nivel_faixas', faixas)}><Icon name="check" size={14} /> Salvar faixas</Button>}
        </div>
      )}

      {sec === 'form' && (
        <div className="space-y-3">
          <Card className="p-4 space-y-3">
            <div><CfgLabel>Instrução de upload (comprovação)</CfgLabel><Area rows={2} value={textos.upload_info} onChange={(e) => setTextos((p) => ({ ...p, upload_info: e.target.value }))} disabled={!canEdit} /></div>
            <div><CfgLabel>Aviso de cadastro (nível não elegível)</CfgLabel><Area rows={2} value={textos.cadastro_info} onChange={(e) => setTextos((p) => ({ ...p, cadastro_info: e.target.value }))} disabled={!canEdit} /></div>
          </Card>
          <Card className="p-4">
            <div className="flex items-center justify-between mb-2">
              <CfgLabel>Espaços de instrução</CfgLabel>
              {canEdit && <button onClick={() => setTextos((p) => ({ ...p, espacos: [...p.espacos, { v: '', l: '' }] }))} className="text-xs font-semibold text-[var(--accent)] inline-flex items-center gap-1"><Icon name="plus" size={13} /> Adicionar</button>}
            </div>
            <div className="space-y-2">
              {textos.espacos.map((o, i) => (
                <div key={i} className="grid grid-cols-[1fr_1.4fr_auto] gap-2 items-center">
                  <Input value={o.v} onChange={(e) => setTextos((p) => ({ ...p, espacos: p.espacos.map((x, idx) => idx === i ? { ...x, v: e.target.value } : x) }))} placeholder="chave" disabled={!canEdit} />
                  <Input value={o.l} onChange={(e) => setTextos((p) => ({ ...p, espacos: p.espacos.map((x, idx) => idx === i ? { ...x, l: e.target.value } : x) }))} placeholder="Rótulo exibido" disabled={!canEdit} />
                  {canEdit && <button onClick={() => setTextos((p) => ({ ...p, espacos: p.espacos.filter((_, idx) => idx !== i) }))} className="text-[var(--red)] p-1.5 cursor-pointer inline-flex" title="Remover" aria-label="Remover espaço de instrução"><Icon name="x" size={14} /></button>}
                </div>
              ))}
            </div>
          </Card>
          {canEdit && <Button variant="primary" disabled={busy} onClick={() => persist('form_textos', { upload_info: textos.upload_info, cadastro_info: textos.cadastro_info, espacos: textos.espacos.filter((e) => e.v && e.l) })}><Icon name="check" size={14} /> Salvar textos</Button>}
        </div>
      )}
    </div>
  );
}
