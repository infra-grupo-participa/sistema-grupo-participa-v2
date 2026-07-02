'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Badge, Button, Modal, ProgressBar } from '@/shared/ui/components';
import './solicitar-placa.css';
import { maskCep, maskCurrency, maskDoc } from './masks';
import { cepLookup, placaDuplicateCheck, placaGet, placaRecover, placaSave, placaUpload } from './placa-api';
import { isPlateEligible } from '../domain/form-progress';
import { TOTAL_STEPS, STEP_NAMES, ESPACOS, NIVEIS, type Form, type View, type FormConfig } from './solicitar-placa-constants';
import { Wrap, SuccessCard, TrackingCard } from './solicitar-placa-parts';
import { StepContent } from './SolicitarPlacaSteps';

export type { FormConfig } from './solicitar-placa-constants';

export function SolicitarPlacaClient({ initialToken, config }: { initialToken: string; config?: FormConfig }) {
  const NIVEIS_CFG = config?.niveis?.length ? config.niveis : NIVEIS;
  const ESPACOS_CFG = config?.textos?.espacos?.length ? config.textos.espacos : ESPACOS;
  const UPLOAD_INFO = config?.textos?.upload_info || 'Faça o upload de um PDF/imagem com contratos, notas fiscais ou extratos que comprovem seu faturamento com Holding Familiar.';
  const CADASTRO_INFO = config?.textos?.cadastro_info || 'Para o seu nível, registramos apenas o cadastro — a placa fica disponível ao atingir um nível elegível.';
  const [view, setView] = useState<View>('loading');
  const [step, setStep] = useState(1);
  const [form, setForm] = useState<Form>({ pais: 'Brasil', faturamento_fmt: '' });
  const [token, setToken] = useState<string>(initialToken || '');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const [tracking, setTracking] = useState<Record<string, unknown> | null>(null);
  const [dup, setDup] = useState<{ email: boolean; documento_nf: boolean }>({ email: false, documento_nf: false });
  const cepSeq = useRef(0);

  const set = (k: string, v: string) => setForm((f) => ({ ...f, [k]: v }));
  const eligible = isPlateEligible(form.nivel);

  // ── Carregamento / resumo de sessão (via token na URL ou cookie gp_placa_session) ──
  useEffect(() => {
    (async () => {
      const r = await placaGet(initialToken, false);
      if (!r?.ok || !r.solicitacao) {
        setView('form');
        return;
      }
      const sol = r.solicitacao as Record<string, unknown>;
      hydrate(sol);
      routeByStatus(sol);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialToken]);

  function hydrate(sol: Record<string, unknown>) {
    setToken(String(sol.token ?? initialToken));
    const f: Form = { pais: String(sol.pais ?? 'Brasil') };
    for (const k of [
      'nome', 'email', 'telefone', 'documento_nf', 'turma', 'profissao', 'telefone_profissional',
      'youtube_url', 'site_profissional', 'instagram_url', 'facebook_url', 'interesse', 'espaco_instrucao',
      'nivel', 'proof_url', 'declaracao_url', 'cep', 'logradouro', 'numero', 'complemento', 'bairro', 'cidade', 'estado_uf',
    ]) {
      if (sol[k] != null) f[k] = String(sol[k]);
    }
    if (sol.faturamento_declarado != null) {
      f.faturamento_declarado = String(sol.faturamento_declarado);
      f.faturamento_fmt = maskCurrency(String(sol.faturamento_declarado));
    }
    setForm((prev) => ({ ...prev, ...f }));
  }

  function routeByStatus(sol: Record<string, unknown>) {
    const status = String(sol.status ?? '');
    if (status === 'cadastro_concluido') {
      setView('cadastro');
    } else if (['enviado', 'em_auditoria', 'docs_aprovados', 'placa_postada', 'concluido', 'rejeitado'].includes(status)) {
      setTracking(sol);
      setView('tracking');
    } else {
      // rascunho — retoma no step do formulário
      const s = Math.min(Math.max(Number(sol.step_index ?? 0) || 1, 1), TOTAL_STEPS);
      setStep(s < 1 ? 1 : s);
      setView('form');
    }
  }

  // ── Persistência por etapa ──
  const buildPayload = useCallback(
    (targetStep: number, status: string): Record<string, unknown> => {
      const p: Record<string, unknown> = { step_index: targetStep, status, pais: form.pais || 'Brasil' };
      const keys = [
        'nome', 'email', 'telefone', 'turma', 'profissao', 'telefone_profissional', 'youtube_url',
        'site_profissional', 'instagram_url', 'facebook_url', 'interesse', 'espaco_instrucao', 'nivel',
        'cep', 'logradouro', 'numero', 'complemento', 'bairro', 'cidade', 'estado_uf',
      ];
      for (const k of keys) if (form[k]) p[k] = form[k];
      if (form.documento_nf) p.documento_nf = form.documento_nf;
      if (eligible && form.faturamento_declarado) p.faturamento_declarado = Number(form.faturamento_declarado);
      // proof/declaracao: só envia URL real; 'uploaded' é ignorado pelo servidor.
      if (form.proof_url && form.proof_url !== 'uploaded') p.proof_url = form.proof_url;
      if (form.declaracao_url && form.declaracao_url !== 'uploaded') p.declaracao_url = form.declaracao_url;
      if (token) p.token = token;
      return p;
    },
    [form, eligible, token],
  );

  async function saveStep(targetStep: number, status: string): Promise<boolean> {
    const res = await placaSave(buildPayload(targetStep, status));
    if (!res?.ok) {
      setErr('Não foi possível salvar. Verifique os dados e tente novamente.');
      return false;
    }
    if (res.token) setToken(res.token);
    return true;
  }

  // ── Validação por etapa ──
  function validStep(n: number): string | null {
    if (n === 1) {
      if (!form.nome || !form.email || !form.telefone || !form.documento_nf || !form.turma) return 'Preencha todos os campos obrigatórios.';
      if (dup.email) return 'Este e-mail já possui uma solicitação.';
      if (dup.documento_nf) return 'Este documento já possui uma solicitação.';
    }
    if (n === 2 && !form.interesse) return 'Selecione uma opção.';
    if (n === 3) {
      if (!form.espaco_instrucao || !form.nivel) return 'Selecione o espaço de instrução e o nível.';
      if (eligible && !form.faturamento_declarado) return 'Informe o faturamento declarado.';
    }
    if (n === 4 && eligible && (!form.proof_url || form.proof_url === '')) return 'Envie o documento comprobatório.';
    if (n === 5 && eligible && (!form.declaracao_url || form.declaracao_url === '')) return 'Envie a declaração assinada.';
    if (n === 6) {
      for (const k of ['cep', 'logradouro', 'numero', 'bairro', 'cidade', 'estado_uf']) if (!form[k]) return 'Preencha o endereço completo.';
    }
    return null;
  }

  async function goNext(n: number) {
    setErr('');
    const v = validStep(n);
    if (v) {
      setErr(v);
      return;
    }
    setBusy(true);
    try {
      if (n === 3 && !eligible) {
        if (await saveStep(3, 'cadastro_concluido')) setView('cadastro');
        return;
      }
      if (n === 6) {
        if (await saveStep(6, 'enviado')) setView('success');
        return;
      }
      if (await saveStep(n, 'rascunho')) setStep(n + 1);
    } finally {
      setBusy(false);
    }
  }

  const goBack = (n: number) => {
    setErr('');
    setStep(Math.max(1, n - 1));
  };

  // ── Duplicate-check (blur) ──
  async function checkDup(field: 'email' | 'documento_nf') {
    const value = field === 'email' ? form.email : (form.documento_nf || '').replace(/\D/g, '');
    if (!value) return;
    const isDup = await placaDuplicateCheck(field, value, token);
    setDup((d) => ({ ...d, [field]: isDup }));
  }

  // ── CEP (debounce) ──
  function onCep(v: string) {
    set('cep', maskCep(v));
    const digits = v.replace(/\D/g, '');
    if (digits.length !== 8) return;
    const seq = ++cepSeq.current;
    setTimeout(async () => {
      if (seq !== cepSeq.current) return;
      const r = await cepLookup(digits);
      if (r && seq === cepSeq.current) {
        setForm((f) => ({
          ...f,
          logradouro: r.logradouro || f.logradouro || '',
          bairro: r.bairro || f.bairro || '',
          cidade: r.cidade || f.cidade || '',
          estado_uf: r.estado_uf || f.estado_uf || '',
        }));
      }
    }, 400);
  }

  // ── Upload ──
  async function onUpload(kind: 'comprovante' | 'declaracao', file: File | null) {
    if (!file || !token) return;
    setBusy(true);
    setErr('');
    const url = await placaUpload(token, kind, file);
    setBusy(false);
    if (!url) {
      setErr('Não foi possível enviar o arquivo. Verifique o formato (PDF/imagem, até 10MB).');
      return;
    }
    set(kind === 'comprovante' ? 'proof_url' : 'declaracao_url', url);
  }

  // ── Recover session ──
  const [recoverOpen, setRecoverOpen] = useState(false);
  const [recoverEmail, setRecoverEmail] = useState('');
  const [recoverDoc, setRecoverDoc] = useState('');
  async function doRecover() {
    setErr('');
    const r = await placaRecover(recoverEmail.trim(), recoverDoc.replace(/\D/g, ''));
    if (r.found && r.solicitacao) {
      setRecoverOpen(false);
      hydrate(r.solicitacao as Record<string, unknown>);
      routeByStatus(r.solicitacao as Record<string, unknown>);
    } else {
      setErr('Nenhuma solicitação encontrada com esses dados.');
    }
  }

  // ── Render ──
  if (view === 'loading') return <Wrap><div className="sp-card"><div className="sp-card-body">Carregando…</div></div></Wrap>;
  if (view === 'success') return <Wrap><SuccessCard kind="success" /></Wrap>;
  if (view === 'cadastro') return <Wrap><SuccessCard kind="cadastro" /></Wrap>;
  if (view === 'tracking' && tracking) return <Wrap><TrackingCard data={tracking} /></Wrap>;

  const pct = Math.round(((step - 1) / TOTAL_STEPS) * 100);

  return (
    <Wrap>
      <div className="sp-track">
        <ProgressBar value={pct} tone="accent" height={8} />
        <div className="sp-meta">
          <Badge tone="accent">Etapa {step} de {TOTAL_STEPS}</Badge>
          <span>{STEP_NAMES[step]}</span>
        </div>
      </div>

      <div className="sp-card">
        <StepContent
          step={step}
          form={form}
          set={set}
          err={err}
          busy={busy}
          dup={dup}
          eligible={eligible}
          checkDup={checkDup}
          onCep={onCep}
          onUpload={onUpload}
          goNext={goNext}
          goBack={goBack}
          onRecover={() => setRecoverOpen(true)}
          espacos={ESPACOS_CFG}
          niveis={NIVEIS_CFG}
          uploadInfo={UPLOAD_INFO}
          cadastroInfo={CADASTRO_INFO}
        />
      </div>

      {recoverOpen && (
        <Modal
          open={recoverOpen}
          onClose={() => setRecoverOpen(false)}
          title="Recuperar solicitação"
          width="max-w-md"
          footer={
            <>
              <Button type="button" variant="ghost" onClick={() => setRecoverOpen(false)}>Cancelar</Button>
              <Button type="button" variant="primary" onClick={doRecover} disabled={busy}>{busy ? 'Aguarde…' : 'Recuperar'}</Button>
            </>
          }
        >
          <p className="text-sm text-[var(--fg-2)] mb-4 leading-relaxed">Informe e-mail e documento usados no cadastro.</p>
          <div className="sp-field"><label>E-mail</label><input type="email" value={recoverEmail} onChange={(e) => setRecoverEmail(e.target.value)} /></div>
          <div className="sp-field"><label>Documento</label><input value={recoverDoc} onChange={(e) => setRecoverDoc(maskDoc(e.target.value))} /></div>
          {err && <p className="sp-err">{err}</p>}
        </Modal>
      )}
    </Wrap>
  );
}
