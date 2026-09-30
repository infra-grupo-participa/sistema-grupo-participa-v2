'use client';

import { useEffect, useId, useMemo, useRef, useState } from 'react';
import {
  type Aluno360,
  ESPACO_LABEL,
  parseInstrucao,
  SITUACAO,
  STATUS_ACESSO,
  RENOVACAO_LABEL,
  renovacaoStatus,
} from '../domain/aluno-360';
import { nivelLabel } from '@/shared/domain/nivel-resultado';
import { loadPlacaHistorico, type Turma, type PlacaHistorico } from './alunos-data';
import { loadCiclosByAluno, type Ciclo } from '@/modules/placas/ui/admin/placas-admin-data';
import { cursoDesempenhoMock } from '../domain/curso-mock';
import { pendenciasAluno, contarPorAba, type PendenciaAluno } from '../domain/pendencias-aluno';
import type { AbaFicha } from '../domain/ficha-aluno-abas';
import { Badge, NivelBadge, Drawer, AvatarInicial, SectionCard, Button, KpiCard, ProgressBar, Tabs, idsAba } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtData } from '@/shared/ui/format';
import { AlunoForm } from './AlunoForm';
import { SecTitle, SubTitle, Section, Row } from './alunos-ui-bits';
import { CorpoTrajetoria } from './TrajetoriaAluno';
import { AlunoAbaJornada } from './AlunoAbaJornada';
import { motivoSemVencimento, sitTone, tel, vinculoSocio, type VinculoSocio } from './alunos-ui-shared';

// Trajetória do aluno: ligada por padrão; NEXT_PUBLIC_ALUNO_TRAJETORIA=off desliga (inlined no build).
const TRAJETORIA_ATIVA = process.env.NEXT_PUBLIC_ALUNO_TRAJETORIA !== 'off';

// Liga a aba "Curso" quando a integração real de desempenho existir (hoje só há mock zerado).
const CURSO_TAB_ATIVA = false as boolean;

/** Abas que existem neste build (Trajetória e Curso dependem de flag). */
const ABAS_DISPONIVEIS: AbaFicha[] = [
  'resumo', 'programa', 'jornada',
  ...(TRAJETORIA_ATIVA ? (['trajetoria'] as const) : []),
  ...(CURSO_TAB_ATIVA ? (['curso'] as const) : []),
];
const ROTULO_ABA: Record<AbaFicha, string> = { resumo: 'Resumo', programa: 'Programa', jornada: 'Jornada', trajetoria: 'Trajetória', curso: 'Curso' };

/**
 * Ficha do aluno em abas. A moldura (cabeçalho, rodapé, abas) fica aqui; o corpo de cada aba
 * monta na 1ª visita e depois só é ocultado (`hidden`) — trocar de aba não refaz consulta
 * (Trajetória, SIP expandido) nem perde o estado aberto dos blocos recolhíveis.
 * Placa e ciclos continuam carregando na abertura: as pendências do Resumo dependem deles.
 */
export function AlunoDrawer({ a, turmas, alunos = [], canEdit, editMode, onToggleEdit, onClose, onAbrirAluno, onSaved, abaInicial, onAbaChange }: {
  a: Aluno360;
  turmas: Turma[];
  /** Base carregada, usada para ligar o sócio ao titular e vice-versa. */
  alunos?: Aluno360[];
  canEdit: boolean;
  editMode: boolean;
  onToggleEdit: () => void;
  onClose: () => void;
  /** Troca a ficha aberta — usado para pular do sócio para o titular e de volta. */
  onAbrirAluno?: (id: string) => void;
  onSaved: (msg: string) => void;
  /** Aba na abertura (link com `#aluno=…&aba=…`). Ausente ou indisponível → Resumo. */
  abaInicial?: AbaFicha | null;
  /** Avisa a aba ativa (inclusive a inicial) — quem abre a ficha grava na URL. */
  onAbaChange?: (aba: AbaFicha) => void;
}) {
  const [placaHist, setPlacaHist] = useState<PlacaHistorico | null>(null);
  const [placaLoading, setPlacaLoading] = useState(false);
  const [ciclos, setCiclos] = useState<Ciclo[]>([]);
  const temPlaca = !!(a.tem_placa || a.tem_solicitacao_placa);
  useEffect(() => {
    if (!temPlaca || placaHist !== null) return;
    setPlacaLoading(true); // eslint-disable-line react-hooks/set-state-in-effect
    loadPlacaHistorico(a.id, a.email)
      .then(setPlacaHist)
      .finally(() => setPlacaLoading(false));
  }, [temPlaca, placaHist, a.id, a.email]);
  // Histórico de níveis (placa + cadastro) por aluno_id — sobrevive à exclusão da solicitação.
  useEffect(() => {
    if (!a.id) return;
    loadCiclosByAluno(a.id).then(setCiclos).catch(() => {});
  }, [a.id]);
  const sit = a.situacao_acesso ? SITUACAO[a.situacao_acesso] : null;
  const espaco = ESPACO_LABEL[a.espaco_instrucao || ''] || null;
  const instr = parseInstrucao(a);
  const vinculo = useMemo(() => vinculoSocio(a, alunos), [a, alunos]);

  // ── Abas ──
  const idBase = `ficha-aluno-${useId().replace(/[^a-zA-Z0-9_-]/g, '')}`;
  const [aba, setAba] = useState<AbaFicha>(() => (abaInicial && ABAS_DISPONIVEIS.includes(abaInicial) ? abaInicial : 'resumo'));
  const [visitadas, setVisitadas] = useState<Set<AbaFicha>>(() => new Set([aba]));
  const focarPainel = useRef(false);
  const trocarAba = (k: AbaFicha, focar = false) => {
    focarPainel.current = focar;
    setAba(k);
    setVisitadas((v) => (v.has(k) ? v : new Set(v).add(k)));
  };
  useEffect(() => { onAbaChange?.(aba); }, [aba, onAbaChange]);
  // Pendência clicada: o botão some com o Resumo; o foco vai para o painel de destino, não para o <body>.
  useEffect(() => {
    if (!focarPainel.current) return;
    focarPainel.current = false;
    document.getElementById(idsAba(idBase, aba).panel)?.focus();
  }, [aba, idBase]);

  const pendencias = useMemo(
    () => pendenciasAluno(a, { socio: vinculo, placa: placaHist?.solicitacao ?? null }),
    [a, vinculo, placaHist],
  );
  const nPorAba = contarPorAba(pendencias);
  const abas = ABAS_DISPONIVEIS.map((k) => ({
    k,
    l: ROTULO_ABA[k],
    n: k === 'programa' || k === 'jornada' ? nPorAba[k] : undefined,
  }));

  const painel = (k: AbaFicha, conteudo: React.ReactNode) => {
    if (!visitadas.has(k)) return null;
    const ids = idsAba(idBase, k);
    return (
      <div key={k} role="tabpanel" id={ids.panel} aria-labelledby={ids.tab} tabIndex={0} hidden={aba !== k} className="space-y-4">
        {conteudo}
      </div>
    );
  };

  return (
    <Drawer
      onClose={onClose}
      title={a.nome || 'Sem nome'}
      subtitle={a.email || '—'}
      badges={
        !editMode ? (
          <>
            {sit && <Badge tone={sitTone(sit.cls)} dot>{sit.label}</Badge>}
            {a.nivel_resultado && <NivelBadge nivel={a.nivel_resultado} />}
            {(a.cidade || a.estado) && <Badge>{[a.cidade, a.estado].filter(Boolean).join(' · ')}</Badge>}
            {instr ? <Badge dotColor={instr.cor}>{instr.label}</Badge> : espaco && <Badge tone="info">{espaco}</Badge>}
            {/* Ser sócio só é útil junto com "de quem" — o badge sozinho obrigava a caçar o titular. */}
            {instr?.ehSocio && (vinculo.titularNome
              ? <Badge tone="accent">Sócio de {vinculo.titularNome}</Badge>
              : <span title="Marcado como sócio, mas sem titular no cadastro"><Badge tone="warning">Sócio · titular não informado</Badge></span>)}
            {!instr?.ehSocio && vinculo.socios.length > 0 && (
              <Badge tone="accent">{vinculo.socios.length === 1 ? '1 sócio' : `${vinculo.socios.length} sócios`}</Badge>
            )}
          </>
        ) : undefined
      }
      avatar={<AvatarInicial nome={a.nome} />}
      width="max-w-5xl"
      footer={canEdit ? <Button size="sm" variant={editMode ? 'ghost' : 'subtle'} onClick={onToggleEdit}><Icon name="pencil" size={13} /> {editMode ? 'Cancelar edição' : 'Editar dados'}</Button> : undefined}
    >
      {/* Edição: a barra de abas some e o formulário ocupa o corpo. Os painéis já visitados ficam
          montados e ocultos, e a aba ativa (estado daqui) volta igual ao salvar ou cancelar. */}
      {editMode && <AlunoForm a={a} turmas={turmas} onSaved={onSaved} />}
      <div hidden={editMode}>
        <Tabs tabs={abas} active={aba} onChange={(k) => trocarAba(k as AbaFicha)} idBase={idBase} label="Seções da ficha do aluno" />

        {painel('resumo', (
          <>
            {/* HERO — resumo operacional em relance (nível, acesso, turma/vencimento, Hotmart) */}
            <HeroResumo a={a} sit={sit} />
            {pendencias.length > 0 && <BlocoPendencias itens={pendencias} onIr={(k) => trocarAba(k, true)} />}
            <SectionCard title={<SecTitle icon="user">Dados Pessoais</SecTitle>}>
              <Section>
                {a.profissao && <Row k="Profissão" v={a.profissao} />}
                <Row k="E-mail" v={a.email} />
                <Row k="Telefone" v={tel(a.telefone)} />
                {a.telefone_profissional && <Row k="Tel. profissional" v={tel(a.telefone_profissional)} />}
                {a.documento && <Row k={a.tipo_documento || 'CPF/CNPJ'} v={a.documento} />}
                <Row k="Endereço" v={[a.endereco_logradouro, a.endereco_numero, a.bairro, a.cidade, a.estado].filter(Boolean).join(', ') || '—'} />
                <div className="flex gap-2 flex-wrap mt-2">
                  {[['Facebook', a.link_facebook], ['Instagram', a.instagram_url], ['YouTube', a.youtube_url], ['Site', a.site_profissional]].filter(([, u]) => u).map(([l, u]) => (
                    <a key={l as string} href={u as string} target="_blank" rel="noopener" className="inline-flex items-center gap-1 text-xs px-2 py-1 rounded-[var(--r-sm)] border border-[var(--border)] text-[var(--accent)] transition-colors hover:border-[var(--border-accent)] hover:bg-[var(--accent-subtle)]"><Icon name="arrow-up-right" size={11} />{l}</a>
                  ))}
                </div>
              </Section>
            </SectionCard>
          </>
        ))}

        {painel('programa', <AbaPrograma a={a} sit={sit} instr={instr} espaco={espaco} vinculo={vinculo} onAbrirAluno={onAbrirAluno} />)}

        {painel('jornada', <AlunoAbaJornada a={a} temPlaca={temPlaca} placaHist={placaHist} placaLoading={placaLoading} ciclos={ciclos} />)}

        {/* Trajetória: a RPC só sai quando a aba abre pela 1ª vez (fn_aluno_trajetoria, cache por aluno). */}
        {TRAJETORIA_ATIVA && painel('trajetoria', <CorpoTrajetoria alunoId={a.id} />)}

        {/* Curso: oculto até existir integração real — cursoDesempenhoMock é 100% zerado
            e exibir métricas falsas confunde a operação. Reativar via CURSO_TAB_ATIVA. */}
        {CURSO_TAB_ATIVA && painel('curso', (
          <SectionCard title={<SecTitle icon="biblioteca">Curso</SecTitle>}>
            <CursoTab />
          </SectionCard>
        ))}
      </div>
    </Drawer>
  );
}

/** Pendências = só os sinais que a ficha já pinta de amarelo/vermelho (ver pendencias-aluno.ts).
 *  Cada linha leva à aba onde o sinal está. */
function BlocoPendencias({ itens, onIr }: { itens: PendenciaAluno[]; onIr: (aba: 'programa' | 'jornada') => void }) {
  return (
    <SectionCard title={<SecTitle icon="alert">Pendências ({itens.length})</SecTitle>}>
      <ul>
        {itens.map((p, i) => (
          <li key={i} className="border-b border-[var(--border-faint)] last:border-0">
            <button
              type="button"
              onClick={() => onIr(p.aba)}
              className="w-full flex items-center justify-between gap-3 py-1.5 text-left hover:bg-[var(--surface-2)]"
            >
              <span className={`text-sm ${p.tom === 'vermelho' ? 'text-[var(--red)]' : 'text-[var(--yellow)]'}`}>{p.texto}</span>
              <span className="text-xs text-[var(--accent)] shrink-0">Ver em {ROTULO_ABA[p.aba]} →</span>
            </button>
          </li>
        ))}
      </ul>
    </SectionCard>
  );
}

/**
 * Aba Programa: Renovação e Vigência fundidas (cada campo uma vez), Acesso ao Curso e Metadados.
 * Antes Turma, Vencimento, Entrou no THB, Data da compra, Oferta, Tipo de oferta e Tempo de acesso
 * apareciam em Renovação E em Acesso ao Curso; UCode em Hotmart E em Metadados; "Registrado no SIP"
 * aqui E no card do SIP (aba Jornada). Ficou uma ocorrência de cada.
 */
function AbaPrograma({ a, sit, instr, espaco, vinculo, onAbrirAluno }: {
  a: Aluno360;
  sit: { label: string; cls: string } | null;
  instr: ReturnType<typeof parseInstrucao>;
  espaco: string | null;
  vinculo: VinculoSocio;
  onAbrirAluno?: (id: string) => void;
}) {
  const rs = renovacaoStatus(a.turma_codigo);
  const info = rs ? RENOVACAO_LABEL[rs] : null;
  const st = a.status_acesso ? STATUS_ACESSO[a.status_acesso] : null;
  return (
    <>
      <div className="grid gap-4 md:grid-cols-2 items-start">
        <SectionCard title={<SecTitle icon="refresh">Renovação e vigência</SecTitle>}>
          <Section>
            {info ? (
              <div className={`p-2.5 rounded-[var(--r-md)] mb-2 text-xs ${rs === 'em_renovacao' ? 'bg-[var(--yellow-subtle)] text-[var(--yellow)]' : 'bg-[var(--red-subtle)] text-[var(--red)]'}`}>
                <span className="inline-flex items-center gap-1.5">{rs === 'em_renovacao' ? <Icon name="refresh" size={12} /> : <Icon name="alert" size={12} />} {info.label}</span>
                <div className="text-[var(--fg-3)] mt-0.5">
                  {rs === 'em_renovacao'
                    ? `Turma ${a.turma_codigo} (T1–T29): segue o processo de renovação.`
                    : `Turma ${a.turma_codigo} (T30+): acesso vencido, sem processo de renovação (em dia, porém não renovado).`}
                </div>
              </div>
            ) : <div className="text-xs text-[var(--fg-3)] mb-2">Sem turma THB definida — status de renovação indisponível.</div>}
            <Row k="Turma THB" v={a.turma_codigo} />
            <Row k="Turma Aurum" v={a.turma_aurum_codigo} />
            {a.placa_aurum && <Row k="Placa Aurum" v={a.placa_aurum} />}
            <Row k="Nível de resultado" v={nivelLabel(a.nivel_resultado) || '—'} />
            <Row k="Renovações" v={a.num_renovacoes == null ? '—' : String(a.num_renovacoes)} />
            <Row k="Regra de acesso" v={a.regra_acesso} />
            <Row k="Tempo de acesso" v={a.tempo_acesso} />
            <Row k="Vencimento" v={a.data_expiracao ? fmtData(a.data_expiracao) : (motivoSemVencimento(a) || (a.situacao_acesso === 'acompanha_titular' ? 'Acompanha titular' : '—'))} />
            {(a.mes_expiracao || a.ano_expiracao) && <Row k="Mês/Ano expiração" v={[a.mes_expiracao, a.ano_expiracao].filter(Boolean).join('/')} />}
            <Row k="Entrou no THB" v={a.data_entrada_thb ? fmtData(a.data_entrada_thb) : '—'} />
            <Row k="Data da compra" v={fmtData(a.data_compra_importada)} />
          </Section>
        </SectionCard>

        <SectionCard title={<SecTitle icon="graduation">Acesso ao Curso</SecTitle>}>
          <Section>
            <div className="flex flex-wrap gap-1.5 mb-2">
              {sit && <Badge tone={sitTone(sit.cls)} dot>{sit.label}</Badge>}
              {st && <Badge tone={st.cls === 'green' ? 'success' : st.cls === 'blue' ? 'info' : 'neutral'}>{st.label}</Badge>}
              {a.status_acesso_central && <Badge tone="neutral">{a.status_acesso_central}</Badge>}
            </div>
            {a.tratamento_manual && <div className="mb-2 p-2 rounded bg-[var(--yellow-subtle)] text-[var(--yellow)] text-xs flex items-center gap-1.5"><Icon name="alert" size={13} /> {a.tratamento_manual}</div>}
            <SubTitle>Produto &amp; oferta</SubTitle>
            <Row k="Produto" v={a.produto} />
            <Row k="Oferta" v={a.oferta} />
            <Row k="Tipo de oferta" v={a.tipo_oferta} />
            <Row k="Origem de acesso" v={a.origem_acesso} />
            {/* Canal de aquisição ≠ origem de acesso: aquele diz por onde a pessoa
                ENTROU (HT 12, ETHB, Acelera), este diz de onde veio o acesso
                (Hotmart, Sócio/Convite). A procedência fica ao lado do canal para
                separar o que é dado do que é regra — é o que sustenta o número
                quando alguém questionar. */}
            <Row k="Canal de aquisição" v={a.canal_aquisicao || '—'} />
            <Row k="Tipo de entrada" v={a.tipo_entrada || '—'} />
            {a.canal_fonte && <Row k="Como foi atribuído" v={a.canal_fonte} />}
            <Row k="Instrução" v={instr ? instr.label : a.instrucao} />
            <Row k="Espaço de instrução" v={espaco} />
            <VinculoSocios a={a} vinculo={vinculo} onAbrirAluno={onAbrirAluno} />
            {(a.cs_estagio || a.cs_responsavel || a.cs_observacoes) && (
              <>
                <SubTitle>Acompanhamento CS</SubTitle>
                {a.cs_estagio && <Row k="Estágio" v={a.cs_estagio} />}
                {a.cs_responsavel && <Row k="Responsável" v={a.cs_responsavel} />}
                {a.cs_observacoes && <Row k="Obs (CS)" v={a.cs_observacoes} />}
              </>
            )}
            {a.obs_central && (
              <>
                <SubTitle>Observações</SubTitle>
                <Row k="Obs central" v={a.obs_central} />
              </>
            )}
            <Collapse title="Hotmart & integrações">
              <Row k="Holding Total (HT)" v={a.tem_ht ? `Sim${a.ativacao_ht_status ? ` · ${a.ativacao_ht_status}` : ''}` : 'Não'} />
              <Row k="Holding Masters (HM)" v={a.tem_hm ? `Sim${a.hm_plano ? ` · ${a.hm_plano}` : ''}` : 'Não'} />
              <Row k="Hotmart UCode" v={a.hotmart_ucode} />
            </Collapse>
          </Section>
        </SectionCard>
      </div>

      {/* Metadados — bloco discreto no fim */}
      <SectionCard title={<SecTitle icon="notebook">Metadados</SecTitle>}>
        <div className="grid sm:grid-cols-2 sm:gap-x-6">
          {a.fonte && <Row k="Fonte" v={a.fonte} />}
          <Row k="Importado em" v={fmtData(a.importado_em)} />
          <Row k="Atualizado em" v={fmtData(a.atualizado_em)} />
        </div>
      </SectionCard>
    </>
  );
}

/**
 * Sociedade: de quem a pessoa é sócia, ou quem são os sócios dela.
 *
 * Só o `eh_socio` não resolve nada na operação — a pergunta real é "sócio de
 * quem?". Quando o titular está na base, o nome vira botão e a ficha dele abre
 * no lugar desta; quando não está (titular fora da Central, por exemplo), o nome
 * aparece como texto, porque saber o nome já responde a pergunta.
 */
function VinculoSocios({ a, vinculo, onAbrirAluno }: {
  a: Aluno360;
  vinculo: VinculoSocio;
  onAbrirAluno?: (id: string) => void;
}) {
  const { titular, socios } = vinculo;
  // FK resolvida (`socio_de_aluno_id`) também conta como sociedade, mesmo sem `eh_socio`
  // marcado ou `socio_de_nome` preenchido — senão o vínculo existe no banco e some da ficha.
  const ehSocio = Boolean(a.eh_socio) || Boolean(vinculo.titularNome) || Boolean(titular);
  const titularNome = vinculo.titularNome || titular?.nome || null;

  const link = (nome: string | null, id?: string) => {
    const texto = nome || 'Sem nome';
    if (!id || !onAbrirAluno) return <span className="text-sm text-[var(--fg)]">{texto}</span>;
    return (
      <button
        type="button"
        onClick={() => onAbrirAluno(id)}
        className="inline-flex items-center gap-1 text-sm text-[var(--accent)] hover:underline text-right"
      >
        {texto}<Icon name="arrow-up-right" size={11} />
      </button>
    );
  };

  if (ehSocio) {
    return (
      <div className="flex justify-between gap-3 py-1 border-b border-[var(--border-faint)]">
        <span className="text-xs text-[var(--fg-3)]">Sócio de</span>
        <span className="text-right">
          {titularNome
            ? link(titularNome, titular?.id)
            : <span className="text-sm text-[var(--yellow)]">Titular não informado</span>}
          {titularNome && !titular && (
            <div className="text-[11px] text-[var(--fg-3)]">titular não está na base carregada</div>
          )}
        </span>
      </div>
    );
  }

  if (!socios.length) return null;
  return (
    <div className="flex justify-between gap-3 py-1 border-b border-[var(--border-faint)]">
      <span className="text-xs text-[var(--fg-3)]">{socios.length === 1 ? 'Sócio' : `Sócios (${socios.length})`}</span>
      <span className="flex flex-col items-end gap-0.5">
        {socios.map((s) => <span key={s.id}>{link(s.nome, s.id)}</span>)}
      </span>
    </div>
  );
}

/** Célula compacta do hero (rótulo minúsculo + valor destacado). */
function MiniStat({ label, tone, i = 0, children }: { label: string; tone?: string; i?: number; children: React.ReactNode }) {
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3 min-w-0 gp-rise" style={{ ...(tone ? { borderLeft: `3px solid ${tone}` } : {}), animationDelay: `${i * 45}ms` }}>
      <div className="text-[10px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{label}</div>
      <div className="text-sm font-semibold text-[var(--fg)] mt-1 truncate">{children}</div>
    </div>
  );
}

/** Tira de resumo operacional no topo da ficha (relance: nível, acesso, turma/venc., Hotmart). */
function HeroResumo({ a, sit }: { a: Aluno360; sit: { label: string; cls: string } | null }) {
  const st = a.status_acesso ? STATUS_ACESSO[a.status_acesso] : null;
  const rs = renovacaoStatus(a.turma_codigo);
  const vencTone = rs ? (rs === 'em_renovacao' ? 'var(--yellow)' : 'var(--red)') : undefined;
  const hotmart = [
    a.tem_ht ? `HT${a.ativacao_ht_status ? ` · ${a.ativacao_ht_status}` : ''}` : null,
    a.tem_hm ? `HM${a.hm_plano ? ` · ${a.hm_plano}` : ''}` : null,
  ].filter(Boolean).join('  •  ');
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
      <MiniStat label="Nível de resultado" tone="var(--accent)" i={0}>
        {a.nivel_resultado ? <NivelBadge nivel={a.nivel_resultado} /> : '—'}
      </MiniStat>
      <MiniStat label="Acesso" i={1}>{st?.label || sit?.label || '—'}</MiniStat>
      <MiniStat label="Turma · Vencimento" tone={vencTone} i={2}>
        <span className="tabular">{(a.turma_codigo || '—') + (a.data_expiracao ? ` · ${fmtData(a.data_expiracao)}` : (motivoSemVencimento(a) ? ` · ${motivoSemVencimento(a)}` : ''))}</span>
      </MiniStat>
      <MiniStat label="Hotmart" i={3}>{hotmart || '—'}</MiniStat>
    </div>
  );
}


/** Seção recolhível para detalhe secundário (corta densidade sem esconder dados). */
function Collapse({ title, children }: { title: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="mt-2 border-t border-[var(--border-faint)] pt-2">
      <button type="button" onClick={() => setOpen((o) => !o)} className="w-full flex items-center justify-between text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] hover:text-[var(--fg-2)] transition-colors">
        <span>{title}</span>
        <span className="inline-flex transition-transform" style={{ transform: open ? 'rotate(180deg)' : 'none' }}><Icon name="chevron-down" size={13} /></span>
      </button>
      {open && <div className="mt-2 space-y-1.5 gp-fade-in">{children}</div>}
    </div>
  );
}

// ── Curso: desempenho (DADOS ILUSTRATIVOS / MOCK) ──
function CursoTab() {
  const m = useMemo(() => cursoDesempenhoMock(), []);
  return (
    <Section>
      <div className="p-2 rounded-[var(--r-md)] bg-[var(--surface-3)] text-[10px] text-[var(--fg-3)] mb-2">
        ⓘ Demonstração de layout — ainda sem integração de progresso de curso. Os valores aparecem zerados de propósito.
      </div>
      <div className="grid grid-cols-3 gap-3 mb-3">
        <KpiCard label="Progresso" value={`${m.progressoGeral}%`} />
        <KpiCard label="Módulos" value={`${m.modulosConcluidos}/${m.modulosTotal}`} />
        <KpiCard label="Aulas" value={`${m.aulasAssistidas}/${m.aulasTotal}`} />
      </div>
      <Row k="Engajamento" v="—" />
      <Row k="Último acesso" v="—" />
      <div className="text-xs font-semibold text-[var(--fg-3)] mt-3 mb-1">Progresso por módulo</div>
      <div className="space-y-2">
        {m.modulos.map((mod) => (
          <div key={mod.nome}>
            <div className="flex justify-between text-xs mb-1">
              <span className="text-[var(--fg-2)]">{mod.nome}</span>
              <span className="text-[var(--fg-3)] tabular">{mod.progresso}%</span>
            </div>
            <ProgressBar value={mod.progresso} height={6} />
          </div>
        ))}
      </div>
    </Section>
  );
}
