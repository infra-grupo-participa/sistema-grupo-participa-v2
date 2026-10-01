'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Button, Loading, Modal } from '@/shared/ui/components';
import './solicitar-placa.css';
import { maskCep, maskCurrency, maskDoc } from './masks';
import { cepLookup, placaDuplicateCheck, placaGet, placaGetSessao, placaRecover, placaRefazer, placaSave, placaUpload } from './placa-api';
import { isPlateEligible, faturamentoBlockReason, NIVEL_MIN_FATURAMENTO, nivelRefazerBlockReason } from '../domain/form-progress';

const NIVEL_NOME: Record<string, string> = {
  iniciante: 'Iniciante',
  em_formacao: 'Em Formação',
  pessoal: 'Pessoal',
  profissional: 'Profissional',
  ouro: 'Ouro',
  platina: 'Platina',
  diamante: 'Diamante',
  diamante_vermelho: 'Diamante Vermelho',
};
import { TOTAL_STEPS, STEP_NAMES, ESPACOS, NIVEIS, TURMAS, mensagemErroServidor, validarArquivoUpload, type Form, type View, type FormConfig } from './solicitar-placa-constants';
import { Wrap, SuccessCard, TrackingCard, Banner, Stepper, AjudaWhatsApp } from './solicitar-placa-parts';
import { StepContent, type UploadEstado, type UploadKind } from './SolicitarPlacaSteps';

export type { FormConfig } from './solicitar-placa-constants';

export function SolicitarPlacaClient({ initialToken, config }: { initialToken: string; config?: FormConfig }) {
  const NIVEIS_CFG = config?.niveis?.length ? config.niveis : NIVEIS;
  const ESPACOS_CFG = config?.textos?.espacos?.length ? config.textos.espacos : ESPACOS;
  const UPLOAD_INFO = config?.textos?.upload_info || 'Faça o upload de um PDF/imagem com contratos, notas fiscais ou extratos que comprovem seu faturamento com Holding Familiar.';
  const CADASTRO_INFO = config?.textos?.cadastro_info || 'Para o seu nível, registramos apenas o cadastro — a placa fica disponível ao atingir um nível elegível.';
  const TURMAS_CFG = config?.turmas?.length ? config.turmas : TURMAS;
  const AJUDA_HREF = config?.ajudaHref || null;
  const [view, setView] = useState<View>('loading');
  const [step, setStep] = useState(1);
  const [form, setForm] = useState<Form>({ pais: 'Brasil', faturamento_fmt: '' });
  const [token, setToken] = useState<string>(initialToken || '');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const [tracking, setTracking] = useState<Record<string, unknown> | null>(null);
  const [dup, setDup] = useState<{ email: boolean; documento_nf: boolean }>({ email: false, documento_nf: false });
  const [cepStatus, setCepStatus] = useState<'' | 'loading' | 'error'>('');
  const [resumed, setResumed] = useState(false);
  const [retorno, setRetorno] = useState('');
  const [fieldErrs, setFieldErrs] = useState<Record<string, string>>({});
  const [uploads, setUploads] = useState<Partial<Record<UploadKind, UploadEstado>>>({});
  /** Aviso de sessão: link antigo resolvido pelo cookie, ou link sem solicitação. */
  const [avisoLink, setAvisoLink] = useState<'' | 'antigo' | 'invalido'>('');
  /** E-mail para onde foi o link pessoal (só na criação, quando o servidor o envia). */
  const [emailLink, setEmailLink] = useState('');
  const [emailLinkEnviado, setEmailLinkEnviado] = useState(false);
  const cepSeq = useRef(0);
  const mounted = useRef(false);

  // Rola ao topo a cada troca de etapa (não no primeiro render).
  useEffect(() => {
    if (!mounted.current) { mounted.current = true; return; }
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }, [step]);

  const set = (k: string, v: string) => {
    setForm((f) => ({ ...f, [k]: v }));
    setFieldErrs((e) => {
      if (!e[k]) return e;
      const { [k]: _omit, ...rest } = e;
      void _omit;
      return rest;
    });
  };
  const eligible = isPlateEligible(form.nivel);

  // ── Carregamento / resumo de sessão (via token na URL ou cookie gp_placa_session) ──
  useEffect(() => {
    (async () => {
      const first = await placaGetSessao(initialToken);
      let r = first.result;
      // Link antigo: o token da URL não existe. O servidor pode já ter caído para o cookie
      // (token_url_invalido); se respondeu 404, tenta de novo só com o cookie de sessão.
      let linkAntigo = Boolean(initialToken && r?.token_url_invalido);
      if (initialToken && first.status === 404) {
        const retry = await placaGetSessao('');
        if (retry.result?.ok && retry.result.solicitacao) {
          r = retry.result;
          linkAntigo = true;
        } else {
          setAvisoLink('invalido');
        }
      }
      if (linkAntigo) {
        limparTokenDaUrl();
        setAvisoLink('antigo');
      }
      if (!r?.ok || !r.solicitacao) {
        setView('form');
        return;
      }
      const sol = r.solicitacao as Record<string, unknown>;
      hydrate(sol, linkAntigo ? String(r.token ?? '') : initialToken);
      routeByStatus(sol);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialToken]);

  /** Tira ?token da barra de endereço sem navegar (o token velho não deve ser favoritado/compartilhado). */
  function limparTokenDaUrl() {
    const u = new URL(window.location.href);
    if (!u.searchParams.has('token')) return;
    u.searchParams.delete('token');
    window.history.replaceState(window.history.state, '', `${u.pathname}${u.search}${u.hash}`);
  }

  function hydrate(sol: Record<string, unknown>, tokenReserva = initialToken) {
    setToken(String(sol.token ?? tokenReserva));
    const f: Form = { pais: String(sol.pais ?? 'Brasil') };
    for (const k of [
      'nome', 'email', 'telefone', 'documento_nf', 'turma', 'profissao', 'telefone_profissional',
      'youtube_url', 'site_profissional', 'instagram_url', 'facebook_url', 'interesse', 'espaco_instrucao',
      'nivel', 'nivel_anterior', 'proof_url', 'declaracao_url', 'cep', 'logradouro', 'numero', 'complemento', 'bairro', 'cidade', 'estado_uf',
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
      setResumed(s > 1);
      const motivo = String(sol.motivo_retorno ?? '').trim();
      setRetorno(motivo);
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
    const eraNovo = !token;
    const res = await placaSave(buildPayload(targetStep, status));
    if (!res?.ok) {
      setErr(mensagemErroServidor(res?.http ?? 0, res?.error));
      return false;
    }
    if (res.token) setToken(res.token);
    // Criação (sem token antes): o servidor envia o link pessoal para o e-mail nesse momento.
    if (eraNovo && res.token && form.email) {
      setEmailLink(form.email.trim());
      setEmailLinkEnviado(res.email_enviado === true);
    }
    return true;
  }

  // ── Validação por etapa ──
  // Falha = mensagem geral (rodapé) + mensagens por campo (na ordem da tela; o 1º recebe o foco).
  type Falha = { msg: string; campos?: Record<string, string> };
  const faltando = (pares: [string, string][]): Falha | null => {
    const campos: Record<string, string> = {};
    for (const [k, m] of pares) if (!form[k]) campos[k] = m;
    const n = Object.keys(campos).length;
    return n ? { msg: n > 1 ? 'Preencha os campos destacados.' : 'Preencha o campo destacado.', campos } : null;
  };
  const noCampo = (k: string, m: string): Falha => ({ msg: 'Corrija o campo destacado.', campos: { [k]: m } });

  function validStep(n: number): Falha | null {
    if (n === 1) {
      const f = faltando([
        ['nome', 'Informe seu nome completo.'],
        ['email', 'Informe seu e-mail.'],
        ['telefone', 'Informe seu WhatsApp.'],
        ['documento_nf', 'Informe seu CPF ou CNPJ.'],
        ['turma', 'Selecione sua turma.'],
      ]);
      if (f) return f;
      if (dup.email) return { msg: 'Este e-mail já possui uma solicitação.' };
      if (dup.documento_nf) return { msg: 'Este documento já possui uma solicitação.' };
    }
    if (n === 2 && !form.interesse) return noCampo('interesse', 'Selecione uma opção.');
    if (n === 3) {
      const f = faltando([
        ['espaco_instrucao', 'Selecione o espaço de instrução.'],
        ['nivel', 'Selecione o seu nível atual.'],
      ]);
      if (f) return f;
      // Refazer: o novo nível precisa ser superior ao concluído (piso = nivel_anterior).
      if (form.nivel_anterior) {
        const motivo = nivelRefazerBlockReason(form.nivel, form.nivel_anterior);
        if (motivo === 'nao_elegivel') return noCampo('nivel', 'Para refazer, selecione um nível a partir de Ouro (que emite placa).');
        if (motivo === 'nao_superior') {
          const nomeAnt = NIVEL_NOME[form.nivel_anterior] ?? form.nivel_anterior;
          return noCampo('nivel', `Seu nível atual é ${nomeAnt}. Escolha um nível superior — este e os inferiores estão bloqueados.`);
        }
      }
      if (eligible && !form.faturamento_declarado) return noCampo('faturamento_declarado', 'Informe o faturamento declarado.');
      if (eligible && form.faturamento_declarado) {
        // Coerência nível × valor (mesma regra do servidor): Diamante com R$ 200k não passa.
        const motivo = faturamentoBlockReason(form.nivel, Number(form.faturamento_declarado));
        if (motivo === 'abaixo_minimo') {
          const nomeNivel = NIVEL_NOME[form.nivel!] ?? form.nivel;
          const min = NIVEL_MIN_FATURAMENTO[form.nivel!];
          return noCampo('faturamento_declarado', `O nível ${nomeNivel} exige faturamento a partir de R$ ${min.toLocaleString('pt-BR')}. Confira o valor digitado ou selecione o nível compatível com o seu faturamento.`);
        }
        if (motivo === 'acima_teto') return noCampo('faturamento_declarado', 'O faturamento informado parece incorreto (valor alto demais). Confira o número digitado.');
      }
    }
    if (n === 4 && eligible && !form.proof_url) return noCampo('proof_url', 'Envie o documento comprobatório.');
    if (n === 5 && eligible && !form.declaracao_url) return noCampo('declaracao_url', 'Envie a declaração assinada.');
    if (n === 6) {
      return faltando([
        ['cep', 'Informe o CEP.'],
        ['logradouro', 'Informe a rua ou avenida.'],
        ['numero', 'Informe o número.'],
        ['bairro', 'Informe o bairro.'],
        ['cidade', 'Informe a cidade.'],
        ['estado_uf', 'Selecione o estado.'],
      ]);
    }
    return null;
  }

  /** Foca e centraliza o 1º campo com erro (ids sp-<chave>, ver SolicitarPlacaSteps). */
  function focarCampo(campos?: Record<string, string>) {
    const primeiro = campos ? Object.keys(campos)[0] : undefined;
    if (!primeiro) return;
    requestAnimationFrame(() => {
      const el = document.getElementById(`sp-${primeiro}`);
      if (!el) return;
      el.focus({ preventScroll: true });
      // Rádio/arquivo podem ser sr-only: centraliza o bloco do campo, não o input invisível.
      (el.closest('.sp-field') ?? el).scrollIntoView({ block: 'center', behavior: 'smooth' });
    });
  }

  async function goNext(n: number) {
    setErr('');
    const v = validStep(n);
    if (v) {
      setErr(v.msg);
      setFieldErrs(v.campos ?? {});
      focarCampo(v.campos);
      return;
    }
    setFieldErrs({});
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
    setFieldErrs({});
    setStep(Math.max(1, n - 1));
  };

  // ── Duplicate-check (blur) + recuperação automática de sessão ──
  async function checkDup(field: 'email' | 'documento_nf') {
    const value = field === 'email' ? form.email : (form.documento_nf || '').replace(/\D/g, '');
    if (!value) return;
    const isDup = await placaDuplicateCheck(field, value, token);
    setDup((d) => ({ ...d, [field]: isDup }));
    // Multi-dispositivo: se já existe cadastro com este e-mail e o documento confere,
    // recupera a sessão na hora (seta o cookie novo) em vez de travar o usuário no erro
    // de duplicado — ele continua de onde parou sem redigitar nada.
    if (isDup) await tryAutoRecover();
  }

  async function tryAutoRecover(): Promise<boolean> {
    const email = (form.email || '').trim();
    const doc = (form.documento_nf || '').replace(/\D/g, '');
    if (!email || (doc.length !== 11 && doc.length !== 14)) return false;
    const r = await placaRecover(email, doc);
    if (!r.found || !r.solicitacao) return false;
    setDup({ email: false, documento_nf: false });
    setErr('');
    hydrate(r.solicitacao as Record<string, unknown>);
    routeByStatus(r.solicitacao as Record<string, unknown>);
    setResumed(true);
    return true;
  }

  // ── CEP (debounce + estado de busca + foco automático) ──
  function onCep(v: string) {
    set('cep', maskCep(v));
    const digits = v.replace(/\D/g, '');
    setCepStatus('');
    if (digits.length !== 8) return;
    const seq = ++cepSeq.current;
    setCepStatus('loading');
    setTimeout(async () => {
      if (seq !== cepSeq.current) return;
      const r = await cepLookup(digits);
      if (seq !== cepSeq.current) return;
      if (r) {
        setForm((f) => ({
          ...f,
          logradouro: r.logradouro || f.logradouro || '',
          bairro: r.bairro || f.bairro || '',
          cidade: r.cidade || f.cidade || '',
          estado_uf: r.estado_uf || f.estado_uf || '',
        }));
        setCepStatus('');
        setFieldErrs((e) => {
          const { logradouro: _l, bairro: _b, cidade: _c, estado_uf: _u, ...rest } = e;
          void _l; void _b; void _c; void _u;
          return rest;
        });
        // Foca o Número: campo que sempre exige preenchimento manual após o CEP.
        requestAnimationFrame(() => {
          const el = document.getElementById('sp-numero') as HTMLInputElement | null;
          if (el && !el.value) el.focus();
        });
      } else {
        setCepStatus('error');
      }
    }, 400);
  }

  // ── Upload ──
  async function onUpload(kind: UploadKind, file: File | null) {
    if (!file || !token) return;
    const campo = kind === 'comprovante' ? 'proof_url' : 'declaracao_url';
    setErr('');
    // Mesma regra do servidor, checada antes de gastar o upload (celular em 4G).
    const invalido = validarArquivoUpload(file);
    if (invalido) {
      setFieldErrs((e) => ({ ...e, [campo]: invalido }));
      setUploads((u) => ({ ...u, [kind]: undefined }));
      return;
    }
    setFieldErrs((e) => {
      const { [campo]: _omit, ...rest } = e;
      void _omit;
      return rest;
    });
    setUploads((u) => ({ ...u, [kind]: { nome: file.name, estado: 'enviando' } }));
    setBusy(true);
    const { url, http } = await placaUpload(token, kind, file);
    setBusy(false);
    if (!url) {
      setUploads((u) => ({ ...u, [kind]: undefined }));
      const msg = http === 400
        ? 'O servidor não aceitou o arquivo. Envie um PDF, JPG, PNG ou WEBP legível, até 10 MB.'
        : http === 404
          ? 'Esta solicitação não aceita mais arquivos. Recarregue a página para ver o andamento.'
          : mensagemErroServidor(http, undefined, 'Não foi possível enviar o arquivo. Tente de novo.');
      setFieldErrs((e) => ({ ...e, [campo]: msg }));
      return;
    }
    setUploads((u) => ({ ...u, [kind]: { nome: file.name, estado: 'enviado' } }));
    set(campo, url);
  }

  // ── Tracking: reflete atualizações do admin (ex.: código de rastreio) sem refresh ──
  useEffect(() => {
    if (view !== 'tracking' || !token) return;
    const id = setInterval(async () => {
      const r = await placaGet(token, false).catch(() => null);
      if (r?.ok && r.solicitacao) setTracking(r.solicitacao as Record<string, unknown>);
    }, 60_000);
    return () => clearInterval(id);
  }, [view, token]);

  // ── Refazer processo (subiu de nível) — só para status 'concluido' ──
  const [refazerBusy, setRefazerBusy] = useState(false);
  const [refazerConfirm, setRefazerConfirm] = useState(false);
  async function doRefazer() {
    if (!token || refazerBusy) return;
    setErr('');
    setRefazerBusy(true);
    const r = await placaRefazer(token);
    setRefazerBusy(false);
    if (!r.ok || !r.solicitacao) {
      setErr(r.error || 'Não foi possível iniciar um novo processo. Tente novamente.');
      return;
    }
    setUploads({});
    setFieldErrs({});
    setRefazerConfirm(false);
    const sol = r.solicitacao as Record<string, unknown>;
    // Novo ciclo: zera o form e re-hidrata só a identidade/endereço; nível e documentos
    // do ciclo anterior NÃO são herdados (o aluno reescolhe um nível superior).
    setForm({ pais: 'Brasil', faturamento_fmt: '' });
    hydrate(sol);
    setForm((f) => ({ ...f, nivel: '', faturamento_declarado: '', faturamento_fmt: '', proof_url: '', declaracao_url: '' }));
    setTracking(null);
    setRetorno('');
    setResumed(false);
    setDup({ email: false, documento_nf: false });
    setStep(1);
    setView('form');
  }

  // ── Recover session (manual — fallback quando o documento não confere) ──
  const [recoverOpen, setRecoverOpen] = useState(false);
  const [recoverEmail, setRecoverEmail] = useState('');
  const [recoverDoc, setRecoverDoc] = useState('');
  const abrirRecover = () => {
    // Pré-preenche com o que o usuário já digitou no formulário (não redigitar).
    setRecoverEmail((form.email || '').trim());
    setRecoverDoc(form.documento_nf || '');
    setRecoverOpen(true);
  };
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
  const avisoLinkEl = avisoLink === 'antigo' ? (
    <Banner tone="info" title="Abrimos a solicitação salva neste aparelho" onClose={() => setAvisoLink('')}>
      <p>O link que você abriu é antigo. Para voltar depois, use o link mais recente enviado ao seu e-mail.</p>
    </Banner>
  ) : avisoLink === 'invalido' ? (
    <Banner tone="warn" title="Não encontramos a solicitação deste link" onClose={() => setAvisoLink('')}>
      <p>Se você já começou, use &quot;Recuperar&quot; com seu e-mail e CPF ou CNPJ. Se não, preencha abaixo.</p>
      <button type="button" className="sp-help" onClick={() => { setAvisoLink(''); abrirRecover(); }}>Recuperar minha solicitação</button>
    </Banner>
  ) : null;
  if (view === 'loading') return <Wrap><div className="sp-card"><div className="sp-card-body"><Loading label="Carregando sua solicitação…" minHeight={160} /></div></div></Wrap>;
  if (view === 'success') return <Wrap><SuccessCard kind="success" token={token} /></Wrap>;

  // Modal de confirmação de refazer/re-solicitar, compartilhado entre a tela de cadastro
  // (< Ouro) e a de acompanhamento (placa concluída). Copy adapta conforme a origem.
  const nivelAtualRaw = String(tracking?.nivel ?? form.nivel ?? '');
  const nomeNivelAtual = NIVEL_NOME[nivelAtualRaw] ?? nivelAtualRaw;
  const refazerDeCadastro = Boolean(nivelAtualRaw) && !isPlateEligible(nivelAtualRaw);
  const refazerModalEl = refazerConfirm ? (
    <Modal
      open={refazerConfirm}
      onClose={() => { if (!refazerBusy) { setRefazerConfirm(false); setErr(''); } }}
      title={refazerDeCadastro ? 'Refazer a solicitação?' : 'Refazer o processo?'}
      width="max-w-md"
      footer={
        <>
          <Button type="button" variant="ghost" onClick={() => { setRefazerConfirm(false); setErr(''); }} disabled={refazerBusy}>Cancelar</Button>
          <Button type="button" variant="primary" onClick={doRefazer} disabled={refazerBusy}>{refazerBusy ? 'Preparando…' : 'Sim, refazer'}</Button>
        </>
      }
    >
      {refazerDeCadastro ? (
        <>
          <p className="text-sm text-[var(--fg-2)] leading-relaxed">
            Seu cadastro está no nível <strong>{nomeNivelAtual || 'atual'}</strong>. Ao refazer, você atualiza sua
            solicitação para um nível <strong>superior</strong> — este nível e os inferiores ficam bloqueados.
          </p>
          <ul className="text-sm text-[var(--fg-2)] leading-relaxed mt-3 space-y-1.5 list-disc pl-5">
            <li>Ao alcançar <strong>Ouro</strong> ou acima, você segue para a emissão da placa.</li>
            <li>Seus dados de contato e endereço já ficam preenchidos.</li>
          </ul>
        </>
      ) : (
        <>
          <p className="text-sm text-[var(--fg-2)] leading-relaxed">
            Você concluiu a placa no nível <strong>{nomeNivelAtual || 'atual'}</strong>. Ao refazer, um novo processo
            começa para um nível <strong>superior</strong> — este nível e os inferiores ficam bloqueados.
          </p>
          <ul className="text-sm text-[var(--fg-2)] leading-relaxed mt-3 space-y-1.5 list-disc pl-5">
            <li>O histórico da sua placa atual é <strong>preservado</strong>.</li>
            <li>Você precisará enviar novamente a <strong>comprovação</strong> e a <strong>declaração</strong> do novo nível.</li>
            <li>Seus dados de contato e endereço já ficam preenchidos.</li>
          </ul>
        </>
      )}
      {err && <p className="sp-err" style={{ marginTop: 12 }}>{err}</p>}
    </Modal>
  ) : null;

  if (view === 'cadastro') {
    return (
      <Wrap>
        {avisoLinkEl}
        <SuccessCard kind="cadastro" onRefazer={() => { setErr(''); setRefazerConfirm(true); }} refazerBusy={refazerBusy} />
        {refazerModalEl}
      </Wrap>
    );
  }
  if (view === 'tracking' && tracking) {
    return (
      <Wrap>
        {avisoLinkEl}
        <TrackingCard data={tracking} onRefazer={() => { setErr(''); setRefazerConfirm(true); }} refazerBusy={refazerBusy} error={err} ajudaHref={AJUDA_HREF} />
        {refazerModalEl}
      </Wrap>
    );
  }

  return (
    <Wrap>
      {avisoLinkEl}
      {emailLink && step > 1 && (emailLinkEnviado ? (
        <Banner tone="info" title="Link pessoal enviado para o seu e-mail" onClose={() => setEmailLink('')}>
          <p>
            Enviamos para <strong>{emailLink}</strong> um link para continuar esta solicitação de outro aparelho.
            Se não encontrar, confira o spam ou a aba Promoções.
          </p>
        </Banner>
      ) : (
        <Banner tone="warn" title="Não conseguimos enviar o link por e-mail" onClose={() => setEmailLink('')}>
          <p>
            Seu progresso está salvo neste aparelho. Para continuar de outro, use <strong>Recuperar</strong> com
            seu e-mail e CPF ou CNPJ.
          </p>
        </Banner>
      ))}
      {retorno && (
        <Banner tone="warn" title="Sua solicitação foi devolvida para correção" onClose={() => setRetorno('')}>
          <p className="mb-2">Nossa equipe revisou seus dados e pediu os seguintes ajustes:</p>
          <div className="sp-banner-quote">{retorno}</div>
          <p className="mt-2 text-xs">Corrija os pontos indicados e envie novamente.</p>
        </Banner>
      )}
      {resumed && !retorno && !form.nivel_anterior && (
        <Banner tone="info" title="Continuamos de onde você parou" onClose={() => setResumed(false)}>
          <p>Seus dados foram recuperados. Revise e siga o preenchimento.</p>
        </Banner>
      )}
      {form.nivel_anterior && !retorno && (
        <Banner tone="info" title="Você subiu de nível 🎉">
          <p>
            Seu nível anterior era <strong>{NIVEL_NOME[form.nivel_anterior] ?? form.nivel_anterior}</strong>.
            Refaça a solicitação normalmente — na etapa <strong>Seu nível</strong>, escolha um nível <strong>superior</strong>:
            o anterior e os inferiores ficam bloqueados.
          </p>
        </Banner>
      )}

      <Stepper step={step} total={TOTAL_STEPS} names={STEP_NAMES} />

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
          cepStatus={cepStatus}
          onUpload={onUpload}
          goNext={goNext}
          goBack={goBack}
          onRecover={abrirRecover}
          espacos={ESPACOS_CFG}
          niveis={NIVEIS_CFG}
          nivelAnterior={form.nivel_anterior || ''}
          uploadInfo={UPLOAD_INFO}
          cadastroInfo={CADASTRO_INFO}
          turmas={TURMAS_CFG}
          fieldErrs={fieldErrs}
          uploads={uploads}
        />
      </div>

      {AJUDA_HREF && (
        <div className="sp-help-foot">
          <span>Precisa de ajuda?</span>
          <AjudaWhatsApp href={AJUDA_HREF} label="Falar com a Secretaria" />
        </div>
      )}

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
          <p className="text-sm text-[var(--fg-2)] mb-4 leading-relaxed">Informe o e-mail e o CPF ou CNPJ usados no cadastro.</p>
          <div className="sp-field"><label htmlFor="sp-rec-email">E-mail</label><input id="sp-rec-email" type="email" value={recoverEmail} onChange={(e) => setRecoverEmail(e.target.value)} autoComplete="email" inputMode="email" /></div>
          <div className="sp-field"><label htmlFor="sp-rec-doc">CPF ou CNPJ</label><input id="sp-rec-doc" value={recoverDoc} onChange={(e) => setRecoverDoc(maskDoc(e.target.value))} inputMode="numeric" autoComplete="off" /></div>
          {err && <p className="sp-err">{err}</p>}
        </Modal>
      )}
    </Wrap>
  );
}
