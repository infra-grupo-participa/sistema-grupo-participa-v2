'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import './solicitar-placa.css';
import { maskPhoneMobile, maskPhoneLandline, maskDoc, maskCep, maskCurrency, currencyDigits } from './masks';
import { cepLookup, placaDuplicateCheck, placaGet, placaRecover, placaSave, placaUpload } from './placa-api';
import { getClientTrackingState, CLIENT_TRACKING_STEPS } from '../domain/client-tracking';
import { isPlateEligible } from '../domain/form-progress';

const TOTAL_STEPS = 6;
const STEP_NAMES = ['', 'Seus dados', 'Interesse', 'Seu nível', 'Comprovação', 'Declaração', 'Endereço'];
const UFS = ['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'];

const INTERESSES = [
  { v: 'pessoal', l: 'Apenas fazer a minha Holding e/ou da minha família' },
  { v: 'familia_e_possivel', l: 'Minha Holding + possibilidade de oferecer a outros clientes' },
  { v: 'profissional', l: 'Trabalhar com Holding Familiar' },
];
const ESPACOS = [
  { v: 'holding_masters', l: 'Holding Masters' },
  { v: 'aurum', l: 'Mentoria Aurum' },
  { v: 'coach_platina', l: 'Coach Platina' },
  { v: 'mastermind', l: 'Mastermind Diamante' },
];
const NIVEIS = [
  { v: 'iniciante', ic: '🌱', nm: 'Iniciante', fx: 'Ainda não comecei' },
  { v: 'em_formacao', ic: '📚', nm: 'Em Formação', fx: 'Estudando o curso' },
  { v: 'pessoal', ic: '👤', nm: 'Pessoal', fx: 'Só minha holding' },
  { v: 'profissional', ic: '💼', nm: 'Profissional', fx: 'Oferecendo a clientes' },
  { v: 'ouro', ic: '🥇', nm: 'Ouro', fx: 'Primeiros R$ 50k faturado' },
  { v: 'platina', ic: '🪙', nm: 'Platina', fx: 'R$ 500k em 12 meses' },
  { v: 'diamante', ic: '💎', nm: 'Diamante', fx: 'R$ 1M em 12 meses' },
  { v: 'diamante_vermelho', ic: '🔴', nm: 'Diamante Vermelho', fx: 'R$ 5M em 12 meses' },
];

type Form = Record<string, string>;
type View = 'loading' | 'form' | 'success' | 'cadastro' | 'tracking' | 'error';

export function SolicitarPlacaClient({ initialToken }: { initialToken: string }) {
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
        <div className="sp-bar"><div className="sp-bar-fill" style={{ width: `${pct}%` }} /></div>
        <div className="sp-meta">
          <span className="sp-badge">Etapa {step} de {TOTAL_STEPS}</span>
          <span>{STEP_NAMES[step]}</span>
        </div>
      </div>

      <div className="sp-card">
        {step === 1 && (
          <Section title="1. Seus dados" subtitle="Preencha seus dados de contato.">
            <div className="sp-grid2">
              <Field label="Nome completo" req><input value={form.nome || ''} onChange={(e) => set('nome', e.target.value)} placeholder="Seu nome completo" /></Field>
              <Field label="E-mail" req><input type="email" value={form.email || ''} onChange={(e) => set('email', e.target.value)} onBlur={() => checkDup('email')} placeholder="seu@email.com" /></Field>
              <Field label="WhatsApp" req><input value={form.telefone || ''} onChange={(e) => set('telefone', maskPhoneMobile(e.target.value))} placeholder="(11) 99999-9999" /></Field>
              <Field label="Documento" req><input value={form.documento_nf || ''} onChange={(e) => set('documento_nf', maskDoc(e.target.value))} onBlur={() => checkDup('documento_nf')} placeholder="CPF ou CNPJ" inputMode="numeric" /></Field>
              <Field label="Turma" req><input value={form.turma || ''} onChange={(e) => set('turma', e.target.value)} placeholder="Ex: T1" maxLength={24} /></Field>
              <Field label="Profissão"><input value={form.profissao || ''} onChange={(e) => set('profissao', e.target.value)} placeholder="Ex: Empresário, Médico…" maxLength={100} /></Field>
              <Field label="Telefone Profissional"><input value={form.telefone_profissional || ''} onChange={(e) => set('telefone_profissional', maskPhoneLandline(e.target.value))} placeholder="(11) 9999-9999" /></Field>
              <Field label="Canal do YouTube"><input value={form.youtube_url || ''} onChange={(e) => set('youtube_url', e.target.value)} placeholder="https://youtube.com/@seucanal" /></Field>
              <Field label="Site Profissional"><input value={form.site_profissional || ''} onChange={(e) => set('site_profissional', e.target.value)} placeholder="https://seusite.com.br" /></Field>
              <Field label="Instagram"><input value={form.instagram_url || ''} onChange={(e) => set('instagram_url', e.target.value)} placeholder="@seuperfil" /></Field>
              <Field label="Facebook"><input value={form.facebook_url || ''} onChange={(e) => set('facebook_url', e.target.value)} placeholder="@seuperfil" /></Field>
            </div>
            {dup.email && <p className="sp-err">Este e-mail já possui uma solicitação. <button className="sp-btn-back" onClick={() => setRecoverOpen(true)}>Recuperar</button></p>}
            {err && <p className="sp-err">{err}</p>}
            <Nav onlyNext busy={busy} onNext={() => goNext(1)} nextLabel="Continuar →" />
          </Section>
        )}

        {step === 2 && (
          <Section title="2. Seu interesse" subtitle="O que você busca com a Holding Familiar?">
            {INTERESSES.map((o) => (
              <label key={o.v} className={`sp-radio ${form.interesse === o.v ? 'sel' : ''}`} onClick={() => set('interesse', o.v)}>{o.l}</label>
            ))}
            {err && <p className="sp-err">{err}</p>}
            <Nav busy={busy} onBack={() => goBack(2)} onNext={() => goNext(2)} nextLabel="Continuar →" />
          </Section>
        )}

        {step === 3 && (
          <Section title="3. Seu nível" subtitle="Considere todos os ativos gerados com Holding Familiar.">
            <div className="sp-field"><label>Espaço de instrução <span className="req">*</span></label>
              {ESPACOS.map((o) => (
                <label key={o.v} className={`sp-radio ${form.espaco_instrucao === o.v ? 'sel' : ''}`} onClick={() => set('espaco_instrucao', o.v)}>{o.l}</label>
              ))}
            </div>
            <div className="sp-field"><label>Nível atual <span className="req">*</span></label>
              <div className="sp-level-grid">
                {NIVEIS.map((o) => (
                  <label key={o.v} className={`sp-level ${form.nivel === o.v ? 'sel' : ''}`} onClick={() => set('nivel', o.v)}>
                    <div className="ic">{o.ic}</div><div className="nm">{o.nm}</div><div className="fx">{o.fx}</div>
                  </label>
                ))}
              </div>
            </div>
            {eligible && (
              <Field label="Faturamento declarado (R$)" req>
                <input value={form.faturamento_fmt || ''} onChange={(e) => { const m = maskCurrency(e.target.value); set('faturamento_fmt', m); set('faturamento_declarado', String(currencyDigits(e.target.value))); }} placeholder="R$ 0" inputMode="numeric" />
                <div className="sp-hint">Valor total gerado com Holding Familiar, em reais.</div>
              </Field>
            )}
            {!eligible && form.nivel && <div className="sp-info">Para o seu nível, registramos apenas o cadastro — a placa fica disponível ao atingir um nível elegível.</div>}
            {err && <p className="sp-err">{err}</p>}
            <Nav busy={busy} onBack={() => goBack(3)} onNext={() => goNext(3)} nextLabel={eligible ? 'Continuar para comprovação →' : 'Concluir cadastro →'} />
          </Section>
        )}

        {step === 4 && (
          <Section title="4. Comprovação" subtitle="Envie os documentos que comprovem o nível informado.">
            <div className="sp-info">Faça o upload de um PDF/imagem com contratos, notas fiscais ou extratos que comprovem seu faturamento com Holding Familiar.</div>
            <div className="sp-warn">⚠️ Certifique-se de que o arquivo esteja legível (PDF ou imagem, até 10MB).</div>
            <Field label="Documento comprobatório (PDF ou imagem)" req>
              <input type="file" accept=".pdf,image/*" onChange={(e) => onUpload('comprovante', e.target.files?.[0] ?? null)} />
              {form.proof_url && <div className="sp-hint">✓ Arquivo enviado.</div>}
            </Field>
            {err && <p className="sp-err">{err}</p>}
            <Nav busy={busy} onBack={() => goBack(4)} onNext={() => goNext(4)} nextLabel="Continuar para declaração →" />
          </Section>
        )}

        {step === 5 && (
          <Section title="5. Declaração" subtitle="Validação formal do nível de faturamento informado.">
            <div className="sp-info"><strong>Passo 1:</strong> baixe o modelo oficial, preencha os campos de identificação e assine — sem alterar o texto base.</div>
            <a className="sp-btn-back" href="/modelos/declaracao-faturamento.pdf" target="_blank" rel="noopener" style={{ display: 'inline-block', marginBottom: 12 }}>⬇️ Baixar Modelo da Declaração</a>
            <div className="sp-warn"><strong>⚠️ Atenção:</strong> após assinar, faça o upload do arquivo original (sem edições no texto base).</div>
            <Field label="Declaração assinada (PDF ou imagem)" req>
              <input type="file" accept=".pdf,image/*" onChange={(e) => onUpload('declaracao', e.target.files?.[0] ?? null)} />
              {form.declaracao_url && <div className="sp-hint">✓ Arquivo enviado.</div>}
            </Field>
            {err && <p className="sp-err">{err}</p>}
            <Nav busy={busy} onBack={() => goBack(5)} onNext={() => goNext(5)} nextLabel="Continuar para endereço →" />
          </Section>
        )}

        {step === 6 && (
          <Section title="6. Endereço de entrega" subtitle="Digite o CEP e aguarde o preenchimento automático.">
            <Field label="CEP" req><input value={form.cep || ''} onChange={(e) => onCep(e.target.value)} placeholder="00000-000" maxLength={9} inputMode="numeric" /></Field>
            <Field label="Logradouro" req><input value={form.logradouro || ''} onChange={(e) => set('logradouro', e.target.value)} placeholder="Rua / Avenida…" /></Field>
            <div className="sp-grid2">
              <Field label="Número" req><input value={form.numero || ''} onChange={(e) => set('numero', e.target.value)} placeholder="123" inputMode="numeric" /></Field>
              <Field label="Complemento"><input value={form.complemento || ''} onChange={(e) => set('complemento', e.target.value)} placeholder="Apto 42…" /></Field>
              <Field label="Bairro" req><input value={form.bairro || ''} onChange={(e) => set('bairro', e.target.value)} placeholder="Bairro" /></Field>
              <Field label="Cidade" req><input value={form.cidade || ''} onChange={(e) => set('cidade', e.target.value)} placeholder="Cidade" /></Field>
            </div>
            <Field label="Estado" req>
              <select value={form.estado_uf || ''} onChange={(e) => set('estado_uf', e.target.value)}>
                <option value="">Selecione…</option>
                {UFS.map((uf) => <option key={uf} value={uf}>{uf}</option>)}
              </select>
            </Field>
            {err && <p className="sp-err">{err}</p>}
            <Nav busy={busy} onBack={() => goBack(6)} onNext={() => goNext(6)} nextLabel="Concluir solicitação ✓" />
          </Section>
        )}
      </div>

      {recoverOpen && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,.5)', display: 'grid', placeItems: 'center', padding: 16 }}>
          <div className="sp-card" style={{ maxWidth: 420 }}>
            <Section title="Recuperar solicitação" subtitle="Informe e-mail e documento usados no cadastro.">
              <Field label="E-mail"><input type="email" value={recoverEmail} onChange={(e) => setRecoverEmail(e.target.value)} /></Field>
              <Field label="Documento"><input value={recoverDoc} onChange={(e) => setRecoverDoc(maskDoc(e.target.value))} /></Field>
              {err && <p className="sp-err">{err}</p>}
              <Nav busy={busy} onBack={() => setRecoverOpen(false)} backLabel="Cancelar" onNext={doRecover} nextLabel="Recuperar" />
            </Section>
          </div>
        </div>
      )}
    </Wrap>
  );
}

function Wrap({ children }: { children: React.ReactNode }) {
  return <div className="sp-wrap">{children}</div>;
}
function Section({ title, subtitle, children }: { title: string; subtitle?: string; children: React.ReactNode }) {
  return (
    <>
      <div className="sp-card-head"><h1>{title}</h1>{subtitle && <p>{subtitle}</p>}</div>
      <div className="sp-card-body">{children}</div>
    </>
  );
}
function Field({ label, req, children }: { label: string; req?: boolean; children: React.ReactNode }) {
  return <div className="sp-field"><label>{label} {req && <span className="req">*</span>}</label>{children}</div>;
}
function Nav({ onBack, onNext, nextLabel, backLabel = '← Voltar', onlyNext, busy }: { onBack?: () => void; onNext: () => void; nextLabel: string; backLabel?: string; onlyNext?: boolean; busy?: boolean }) {
  return (
    <div className="sp-nav">
      {!onlyNext && onBack ? <button type="button" className="sp-btn-back" onClick={onBack}>{backLabel}</button> : <span />}
      <button type="button" className="sp-btn-next" onClick={onNext} disabled={busy}>{busy ? 'Aguarde…' : nextLabel}</button>
    </div>
  );
}

function SuccessCard({ kind }: { kind: 'success' | 'cadastro' }) {
  const isCad = kind === 'cadastro';
  return (
    <div className="sp-card">
      <div className="sp-card-body sp-success">
        <div className="em">{isCad ? '✅' : '🎉'}</div>
        <h1 style={{ fontSize: 22, fontWeight: 800, marginTop: 8 }}>{isCad ? 'Cadastro registrado com sucesso!' : 'Recebemos sua solicitação!'}</h1>
        <p style={{ color: '#6b7280', marginTop: 8 }}>
          {isCad
            ? 'Registramos seus dados e o seu nível atual. Como este nível ainda não entra no fluxo da placa, nenhuma documentação adicional é necessária agora.'
            : 'Recebemos seus dados e vamos seguir com a análise da documentação. O acompanhamento fica resumido aos marcos principais do processo.'}
        </p>
      </div>
    </div>
  );
}

function TrackingCard({ data }: { data: Record<string, unknown> }) {
  const { activeIndex } = getClientTrackingState(data);
  const rastreio = String(data.codigo_rastreio ?? '');
  return (
    <div className="sp-card">
      <div className="sp-card-head" style={{ background: '#f29725', color: '#fff' }}>
        <h1 style={{ color: '#fff' }}>Acompanhe sua solicitação</h1>
        <p style={{ color: 'rgba(255,255,255,.85)' }}>Sua solicitação está em andamento</p>
      </div>
      <div className="sp-card-body">
        <div className="sp-tl">
          {CLIENT_TRACKING_STEPS.map((s, i) => {
            const cls = i < activeIndex ? 'done' : i === activeIndex ? 'current' : '';
            return (
              <div key={s.title} className={`sp-tl-step ${cls}`}>
                <div className="sp-tl-bullet">{i < activeIndex ? '✓' : i + 1}</div>
                <div><div className="sp-tl-label">{s.title}</div><div className="sp-tl-note">{s.note}</div></div>
              </div>
            );
          })}
        </div>
        {rastreio && (
          <div className="sp-info" style={{ marginTop: 16 }}>Código de rastreio: <strong>{rastreio}</strong></div>
        )}
      </div>
    </div>
  );
}
