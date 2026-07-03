'use client';

// Conteúdo das 6 etapas do wizard. Estado e handlers vêm do orquestrador (SolicitarPlacaClient) via props.

import { Button } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { maskPhoneMobile, maskPhoneLandline, maskDoc, maskCurrency, currencyDigits } from './masks';
import { INTERESSES, UFS, TURMAS, type Form } from './solicitar-placa-constants';
import { Section, Field, Nav } from './solicitar-placa-parts';
import { ProfissaoAutocomplete } from './ProfissaoAutocomplete';
import { faturamentoBlockReason, NIVEL_MIN_FATURAMENTO, nivelSugeridoPorFaturamento } from '../domain/form-progress';

/** Feedback em tempo real da coerência nível × faturamento declarado (a validação dura fica no goNext/servidor). */
function FaturamentoCoerencia({ nivel, valor, niveis }: { nivel?: string; valor: number; niveis: { v: string; nm: string }[] }) {
  if (!nivel || !valor) return null;
  const nome = (v: string) => niveis.find((n) => n.v === v)?.nm ?? v;
  const motivo = faturamentoBlockReason(nivel, valor);
  if (motivo === 'abaixo_minimo') {
    return (
      <div className="sp-hint sp-hint-warn">
        O nível {nome(nivel)} exige faturamento a partir de R$ {NIVEL_MIN_FATURAMENTO[nivel].toLocaleString('pt-BR')}. Confira o valor ou ajuste o nível.
      </div>
    );
  }
  if (motivo === 'acima_teto') {
    return <div className="sp-hint sp-hint-warn">Esse valor parece alto demais — confira o número digitado.</div>;
  }
  const sugestao = nivelSugeridoPorFaturamento(valor);
  if (sugestao && sugestao !== nivel && NIVEL_MIN_FATURAMENTO[sugestao] > (NIVEL_MIN_FATURAMENTO[nivel] ?? 0)) {
    return (
      <div className="sp-hint">
        💡 Com esse faturamento, você pode se qualificar para o nível <strong>{nome(sugestao)}</strong>.
      </div>
    );
  }
  return null;
}

export interface StepProps {
  step: number;
  form: Form;
  set: (k: string, v: string) => void;
  err: string;
  busy: boolean;
  dup: { email: boolean; documento_nf: boolean };
  eligible: boolean;
  checkDup: (field: 'email' | 'documento_nf') => void;
  onCep: (v: string) => void;
  cepStatus: '' | 'loading' | 'error';
  onUpload: (kind: 'comprovante' | 'declaracao', file: File | null) => void;
  goNext: (n: number) => void;
  goBack: (n: number) => void;
  onRecover: () => void;
  espacos: { v: string; l: string }[];
  niveis: { v: string; ic: string; nm: string; fx: string }[];
  uploadInfo: string;
  cadastroInfo: string;
}

export function StepContent(p: StepProps) {
  const { step, form, set, err, busy, dup, eligible, checkDup, onCep, cepStatus, onUpload, goNext, goBack, onRecover, espacos, niveis, uploadInfo, cadastroInfo } = p;

  if (step === 1) {
    return (
      <Section title="1. Seus dados" subtitle="Preencha seus dados de contato.">
        <div className="sp-grid2">
          <Field label="Nome completo" req><input value={form.nome || ''} onChange={(e) => set('nome', e.target.value)} placeholder="Seu nome completo" autoComplete="name" /></Field>
          <Field label="E-mail" req><input type="email" value={form.email || ''} onChange={(e) => set('email', e.target.value)} onBlur={() => checkDup('email')} placeholder="seu@email.com" autoComplete="email" inputMode="email" /></Field>
          <Field label="WhatsApp" req><input value={form.telefone || ''} onChange={(e) => set('telefone', maskPhoneMobile(e.target.value))} placeholder="(11) 99999-9999" autoComplete="tel-national" inputMode="numeric" /></Field>
          <Field label="Documento" req><input value={form.documento_nf || ''} onChange={(e) => set('documento_nf', maskDoc(e.target.value))} onBlur={() => checkDup('documento_nf')} placeholder="CPF ou CNPJ" inputMode="numeric" autoComplete="off" /></Field>
          <Field label="Turma" req>
            <select value={form.turma || ''} onChange={(e) => set('turma', e.target.value)}>
              <option value="">Selecione sua turma…</option>
              {TURMAS.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
          </Field>
          <Field label="Profissão"><ProfissaoAutocomplete value={form.profissao || ''} onChange={(v) => set('profissao', v)} /></Field>
          <Field label="Telefone Profissional"><input value={form.telefone_profissional || ''} onChange={(e) => set('telefone_profissional', maskPhoneLandline(e.target.value))} placeholder="(11) 9999-9999" inputMode="numeric" autoComplete="tel" /></Field>
          <Field label="Canal do YouTube"><input value={form.youtube_url || ''} onChange={(e) => set('youtube_url', e.target.value)} placeholder="https://youtube.com/@seucanal" /></Field>
          <Field label="Site Profissional"><input value={form.site_profissional || ''} onChange={(e) => set('site_profissional', e.target.value)} placeholder="https://seusite.com.br" /></Field>
          <Field label="Instagram"><input value={form.instagram_url || ''} onChange={(e) => set('instagram_url', e.target.value)} placeholder="@seuperfil" /></Field>
          <Field label="Facebook"><input value={form.facebook_url || ''} onChange={(e) => set('facebook_url', e.target.value)} placeholder="@seuperfil" /></Field>
        </div>
        {dup.email && <p className="sp-err">Este e-mail já possui uma solicitação. <Button type="button" variant="ghost" size="sm" onClick={onRecover}>Recuperar</Button></p>}
        {err && <p className="sp-err">{err}</p>}
        <Nav onlyNext busy={busy} onNext={() => goNext(1)} nextLabel="Continuar →" />
      </Section>
    );
  }

  if (step === 2) {
    return (
      <Section title="2. Seu interesse" subtitle="O que você busca com a Holding Familiar?">
        {INTERESSES.map((o) => (
          <label key={o.v} className={`sp-radio ${form.interesse === o.v ? 'sel' : ''}`}>
            <input type="radio" name="interesse" value={o.v} checked={form.interesse === o.v} onChange={() => set('interesse', o.v)} className="sr-only" />
            <span className="block font-medium">{o.l}</span>
            <span className="block text-xs opacity-70 mt-0.5">{o.sub}</span>
          </label>
        ))}
        {err && <p className="sp-err">{err}</p>}
        <Nav busy={busy} onBack={() => goBack(2)} onNext={() => goNext(2)} nextLabel="Continuar →" />
      </Section>
    );
  }

  if (step === 3) {
    return (
      <Section title="3. Seu nível" subtitle="Considere todos os ativos gerados com Holding Familiar.">
        <div className="sp-field"><label>Espaço de instrução <span className="req">*</span></label>
          <div className="sp-hint" style={{ marginTop: 0, marginBottom: 8 }}>Selecione o ambiente em que você acompanha sua formação para mantermos seu cadastro organizado corretamente.</div>
          {espacos.map((o) => (
            <label key={o.v} className={`sp-radio ${form.espaco_instrucao === o.v ? 'sel' : ''}`}>
              <input type="radio" name="espaco_instrucao" value={o.v} checked={form.espaco_instrucao === o.v} onChange={() => set('espaco_instrucao', o.v)} className="sr-only" />
              {o.l}
            </label>
          ))}
        </div>
        <div className="sp-info">Considere todos os ativos gerados trabalhando com Holding Familiar, incluindo Sessões de Viabilidade, Croquis Estruturais e outros serviços relacionados ao tema.</div>
        <div className="sp-field"><label>Nível atual <span className="req">*</span></label>
          <div className="sp-level-grid">
            {niveis.map((o) => (
              <label key={o.v} data-nivel={o.v} className={`sp-level ${form.nivel === o.v ? 'sel' : ''}`}>
                <input type="radio" name="nivel" value={o.v} checked={form.nivel === o.v} onChange={() => set('nivel', o.v)} className="sr-only" />
                <div className="ic"><Icon name={o.ic} size={22} /></div><div className="nm">{o.nm}</div><div className="fx">{o.fx}</div>
              </label>
            ))}
          </div>
        </div>
        {eligible && (
          <Field label="Faturamento declarado (R$)" req>
            <input value={form.faturamento_fmt || ''} onChange={(e) => { const m = maskCurrency(e.target.value); set('faturamento_fmt', m); set('faturamento_declarado', String(currencyDigits(e.target.value))); }} onFocus={() => { if (!form.faturamento_fmt) set('faturamento_fmt', 'R$ '); }} onBlur={() => { if (form.faturamento_fmt === 'R$ ') set('faturamento_fmt', ''); }} placeholder="R$ 0" inputMode="numeric" />
            <div className="sp-hint">Valor total gerado com Holding Familiar, em reais.</div>
            <FaturamentoCoerencia nivel={form.nivel} valor={Number(form.faturamento_declarado || 0)} niveis={niveis} />
          </Field>
        )}
        {!eligible && form.nivel && <div className="sp-info">{cadastroInfo}</div>}
        {err && <p className="sp-err">{err}</p>}
        <Nav busy={busy} onBack={() => goBack(3)} onNext={() => goNext(3)} nextLabel={eligible ? 'Continuar para comprovação →' : 'Concluir cadastro →'} />
      </Section>
    );
  }

  if (step === 4) {
    return (
      <Section title="4. Comprovação" subtitle="Envie os documentos que comprovem o nível informado.">
        <div className="sp-info">{uploadInfo}</div>
        <div className="sp-warn"><Icon name="alert" size={14} /> Certifique-se de que o arquivo esteja legível (PDF ou imagem, até 10MB).</div>
        <Field label="Documento comprobatório (PDF ou imagem)" req>
          <input type="file" accept=".pdf,image/*" onChange={(e) => onUpload('comprovante', e.target.files?.[0] ?? null)} />
          {form.proof_url && <div className="sp-hint"><Icon name="check" size={13} /> Arquivo enviado.</div>}
        </Field>
        {err && <p className="sp-err">{err}</p>}
        <Nav busy={busy} onBack={() => goBack(4)} onNext={() => goNext(4)} nextLabel="Continuar para declaração →" />
      </Section>
    );
  }

  if (step === 5) {
    const abrirDeclaracao = () => {
      if (!form.nivel) return;
      const qs = new URLSearchParams();
      if (form.nome) qs.set('nome', form.nome);
      if (form.profissao) qs.set('profissao', form.profissao);
      if (form.cidade) qs.set('cidade', form.cidade);
      if (form.estado_uf) qs.set('estado_uf', form.estado_uf);
      qs.set('nivel', form.nivel);
      window.open(`/modelos/declaracao-template.html?${qs.toString()}`, '_blank', 'noopener,noreferrer');
    };
    return (
      <Section title="5. Declaração" subtitle="Validação formal do nível de faturamento informado.">
        <div className="sp-decl-flow">
          <div className="sp-decl-step">
            <span className="n">1</span>
            <div><b>Gere o modelo</b><p>Abrimos a declaração oficial já preenchida com seus dados.</p></div>
          </div>
          <div className="sp-decl-step">
            <span className="n">2</span>
            <div><b>Imprima e assine</b><p>Em papel timbrado, complete as lacunas e assine à mão — sem alterar o texto base.</p></div>
          </div>
          <div className="sp-decl-step">
            <span className="n">3</span>
            <div><b>Envie o arquivo</b><p>Digitalize (PDF ou foto legível) e faça o upload aqui embaixo.</p></div>
          </div>
        </div>
        <button type="button" className="sp-btn-next w-full inline-flex items-center justify-center gap-2" onClick={abrirDeclaracao} style={{ marginBottom: 14 }}>
          <Icon name="file" size={16} /> Gerar declaração preenchida
        </button>
        <div className="sp-warn"><strong className="inline-flex items-center gap-1.5"><Icon name="alert" size={14} /> Atenção:</strong> após assinar, envie o arquivo original (sem edições no texto base).</div>
        <Field label="Declaração assinada (PDF ou imagem)" req>
          <input type="file" accept=".pdf,image/*" onChange={(e) => onUpload('declaracao', e.target.files?.[0] ?? null)} />
          {form.declaracao_url && <div className="sp-hint"><Icon name="check" size={13} /> Arquivo enviado.</div>}
        </Field>
        {err && <p className="sp-err">{err}</p>}
        <Nav busy={busy} onBack={() => goBack(5)} onNext={() => goNext(5)} nextLabel="Continuar para endereço →" />
      </Section>
    );
  }

  if (step === 6) {
    return (
      <Section title="6. Endereço de entrega" subtitle="Digite o CEP e aguarde o preenchimento automático.">
        <Field label="CEP" req>
          <input value={form.cep || ''} onChange={(e) => onCep(e.target.value)} placeholder="00000-000" maxLength={9} inputMode="numeric" autoComplete="postal-code" />
          {cepStatus === 'loading' && <div className="sp-hint">Buscando endereço…</div>}
          {cepStatus === 'error' && <div className="sp-hint sp-hint-warn">CEP não encontrado. Preencha o endereço manualmente.</div>}
        </Field>
        <Field label="Logradouro" req><input value={form.logradouro || ''} onChange={(e) => set('logradouro', e.target.value)} placeholder="Rua / Avenida…" autoComplete="address-line1" /></Field>
        <div className="sp-grid2">
          <Field label="Número" req><input id="sp-numero" value={form.numero || ''} onChange={(e) => set('numero', e.target.value)} placeholder="123" inputMode="numeric" autoComplete="address-line2" /></Field>
          <Field label="Complemento"><input value={form.complemento || ''} onChange={(e) => set('complemento', e.target.value)} placeholder="Apto 42…" autoComplete="address-line3" /></Field>
          <Field label="Bairro" req><input value={form.bairro || ''} onChange={(e) => set('bairro', e.target.value)} placeholder="Bairro" autoComplete="address-level3" /></Field>
          <Field label="Cidade" req><input value={form.cidade || ''} onChange={(e) => set('cidade', e.target.value)} placeholder="Cidade" autoComplete="address-level2" /></Field>
        </div>
        <Field label="Estado" req>
          <select value={form.estado_uf || ''} onChange={(e) => set('estado_uf', e.target.value)} autoComplete="address-level1">
            <option value="">Selecione…</option>
            {UFS.map((uf) => <option key={uf} value={uf}>{uf}</option>)}
          </select>
        </Field>
        {err && <p className="sp-err">{err}</p>}
        <Nav busy={busy} onBack={() => goBack(6)} onNext={() => goNext(6)} nextLabel="Concluir solicitação" />
      </Section>
    );
  }

  return null;
}
