'use client';

// Detalhe da ficha de disparo (os 7 itens do playbook, seção 7, + decisão do gestor) e a gaveta de nova ficha.
import { useMemo, useState } from 'react';
import { Badge, Button, Checkbox, Drawer, FilterSelect, Input, Modal, SectionTitle, Textarea } from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import type { NovaFicha } from '../../application/ports';
import {
  produto as produtoDe, PRODUTOS, ROTULO_STATUS_FICHA, ROTULO_SUPRESSAO, SUPRESSOES_OBRIGATORIAS, TOM_STATUS_FICHA,
} from '../../domain/catalogo';
import { montarSck } from '../../domain/regras';
import type { Contato, FichaDisparo, Negocio, ProdutoKey, Template, Vendedor } from '../../domain/types';
import { Aviso, Campo, FaixaNumeros } from '../comum';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';
import { INFO_DISPARO } from './indicadores';
import { conflitosCom, partesTemplate, simularSupressoes, taxasResultado } from './regras-disparo';

export const NUMERO_OFICIAL = 'Comercial oficial (API)';

/** Texto do template com as variáveis {{x}} destacadas (neutro: âmbar é só seleção/ação). */
export function TextoTemplate({ texto }: { texto: string }) {
  return (
    <span>
      {partesTemplate(texto).map((p, i) => p.variavel
        ? <mark key={i} className="rounded-[var(--r-sm)] bg-[var(--surface-4)] px-1 font-semibold text-[var(--fg)]">{p.texto}</mark>
        : <span key={i}>{p.texto}</span>)}
    </span>
  );
}

function Item({ n, titulo, children }: { n: number; titulo: string; children: React.ReactNode }) {
  return (
    <div className="flex gap-3 py-3 border-b border-[var(--border-faint)] last:border-0">
      <span className="w-6 h-6 shrink-0 grid place-items-center rounded-full bg-[var(--surface-3)] text-[11px] font-semibold tabular text-[var(--fg-2)]" aria-hidden="true">{n}</span>
      <div className="min-w-0 flex-1">
        <div className="text-xs text-[var(--fg-3)]"><span className="sr-only">{n}. </span>{titulo}</div>
        <div className="mt-0.5 text-sm text-[var(--fg)]">{children}</div>
      </div>
    </div>
  );
}

export function DetalheFicha({ f, templates, nomeDe, gestor, onDecidir, onClose }: {
  f: FichaDisparo; templates: Template[]; nomeDe: (id: string | null) => string; gestor: boolean;
  onDecidir: (aprovar: boolean) => void; onClose: () => void;
}) {
  const t = templates.find((x) => x.id === f.templateId);
  const faltando = SUPRESSOES_OBRIGATORIAS.filter((s) => !f.supressoes.includes(s));
  const tx = f.resultado ? taxasResultado(f.resultado) : null;
  const decide = gestor && f.status === 'aguardando_aprovacao';
  return (
    <Modal
      onClose={onClose}
      width="max-w-2xl"
      title={<span className="inline-flex items-center gap-2">Ficha {f.codigo} <Badge tone={TOM_STATUS_FICHA[f.status]}>{ROTULO_STATUS_FICHA[f.status]}</Badge></span>}
      footer={decide ? (
        <>
          {/* Destrutivo à esquerda; primário por último, à direita. */}
          <Button size="sm" variant="danger" onClick={() => onDecidir(false)}><Icon name="x" size={13} /> Reprovar</Button>
          <span className="flex-1" />
          <Button size="sm" variant="ghost" onClick={onClose}>Agora não</Button>
          <Button size="sm" onClick={() => onDecidir(true)}><Icon name="check" size={13} /> Aprovar</Button>
        </>
      ) : <Button size="sm" variant="ghost" onClick={onClose}>Fechar</Button>}
    >
      {decide && (
        <Aviso tom="warning" titulo="Aguardando sua decisão" className="mb-3">
          Confira supressões, template e link antes de aprovar. Aprovada, a ficha entra na agenda.
        </Aviso>
      )}
      {f.resultado && tx && (
        <FaixaNumeros
          className="mb-3"
          itens={[
            { rotulo: 'Entregues', valor: f.resultado.entregues.toLocaleString('pt-BR'), info: INFO_DISPARO.entregues },
            { rotulo: 'Lidas', valor: `${f.resultado.lidas.toLocaleString('pt-BR')} · ${tx.leitura}%`, info: INFO_DISPARO.leitura },
            { rotulo: 'Respostas', valor: `${f.resultado.respostas.toLocaleString('pt-BR')} · ${tx.resposta}%`, info: INFO_DISPARO.resposta },
            { rotulo: 'Falhas', valor: `${f.resultado.falhas.toLocaleString('pt-BR')} · ${tx.falha}%`, alerta: f.resultado.falhas > 0, info: INFO_DISPARO.falhas },
          ]}
        />
      )}
      <Item n={1} titulo="Código do disparo">
        <span className="tabular font-semibold">{f.codigo}</span>
        <span className="block text-xs text-[var(--fg-3)]">O mesmo no template, no log e no utm_content.</span>
      </Item>
      <Item n={2} titulo="Objetivo e produto">
        {f.objetivo}
        <span className="block text-xs text-[var(--fg-3)]">{produtoDe(f.produto).nome}</span>
      </Item>
      <Item n={3} titulo="Lista">
        {f.filtro || '—'}
        <span className="block text-xs text-[var(--fg-3)]">{f.quantidade.toLocaleString('pt-BR')} contatos, deduplicada por e-mail ou DDD + últimos 8 dígitos do telefone.</span>
      </Item>
      <Item n={4} titulo="Supressões aplicadas">
        <ul className="space-y-1">
          {SUPRESSOES_OBRIGATORIAS.map((s) => {
            const ok = f.supressoes.includes(s);
            return (
              <li key={s} className="flex items-center gap-2 text-sm">
                <Icon name={ok ? 'check' : 'x'} size={13} className={ok ? 'text-[var(--fg-3)]' : 'text-[var(--red)]'} />
                <span className={ok ? '' : 'text-[var(--red)]'}>{ROTULO_SUPRESSAO[s]}{ok ? '' : ' · não aplicada'}</span>
              </li>
            );
          })}
        </ul>
        <span className="block mt-1 text-xs text-[var(--fg-3)] tabular">{f.suprimidos.toLocaleString('pt-BR')} suprimidos · {(f.quantidade - f.suprimidos).toLocaleString('pt-BR')} recebem.</span>
        {faltando.length > 0 && <p className="mt-1 text-xs text-[var(--fg-2)]">Ficha antiga sem todas as supressões obrigatórias. Toda ficha nova aplica as quatro.</p>}
      </Item>
      <Item n={5} titulo="Template aprovado e número de envio">
        {t ? (
          <>
            <span className="inline-flex flex-wrap items-center gap-2 font-medium">{t.nome} <Badge tone={t.aprovado ? 'success' : 'warning'}>{t.aprovado ? 'aprovado' : 'pendente'}</Badge></span>
            <p className="mt-1 text-[13px] text-[var(--fg-2)]"><TextoTemplate texto={t.texto} /></p>
          </>
        ) : '—'}
        <span className="block mt-1 text-xs text-[var(--fg-3)]">Número: {f.numeroEnvio}</span>
      </Item>
      <Item n={6} titulo="Data, hora e quem opera">
        <span className="tabular">{fmtDataHora(f.agendadoPara)}</span> · {nomeDe(f.operadorId)}
        {f.aprovadoPor && <span className="block text-xs text-[var(--fg-3)]">{f.status === 'reprovada' ? 'Reprovada' : 'Aprovada'} por {nomeDe(f.aprovadoPor)}</span>}
      </Item>
      <Item n={7} titulo="Link rastreável">
        {f.link ? <span className="break-all text-[13px]">{f.link}</span> : <span className="text-[var(--red)]">Sem link: não sai sem SCK.</span>}
      </Item>
    </Modal>
  );
}

/** 'YYYY-MM-DDTHH:mm' local para o input datetime-local. */
function paraInputLocal(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

/** Bloco da ficha: os itens do playbook, separados por hairline (sem caixa dentro de caixa). */
function Secao({ n, titulo, children }: { n: number; titulo: string; children: React.ReactNode }) {
  return (
    <fieldset className="min-w-0 border-t border-[var(--border-faint)] pt-4 first:border-0 first:pt-0">
      <legend className="sr-only">{n}. {titulo}</legend>
      <SectionTitle>{n} · {titulo}</SectionTitle>
      <div className="space-y-3">{children}</div>
    </fieldset>
  );
}

export function NovaFichaModal({ eu, gestor, contatos, negocios, templates, fichas, agora, onSalvar, onClose }: {
  eu: Vendedor; gestor: boolean; contatos: Contato[]; negocios: Negocio[]; templates: Template[]; fichas: FichaDisparo[];
  agora: Date; onSalvar: (f: NovaFicha, enviar: boolean) => Promise<string | null>; onClose: () => void;
}) {
  const amanha10 = useMemo(() => { const d = new Date(agora); d.setDate(d.getDate() + 1); d.setHours(10, 0, 0, 0); return d; }, [agora]);
  const [objetivo, setObjetivo] = useState('');
  const [prod, setProd] = useState<ProdutoKey>('hm');
  const [filtro, setFiltro] = useState('');
  const [qtd, setQtd] = useState('');
  const aprovados = templates.filter((t) => t.aprovado);
  const [templateId, setTemplateId] = useState(aprovados[0]?.id ?? '');
  const [quando, setQuando] = useState(paraInputLocal(amanha10));
  const [acao, setAcao] = useState('disparo');
  const [link, setLink] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  const sim = useMemo(() => simularSupressoes(contatos, negocios, prod, agora), [contatos, negocios, prod, agora]);
  const dataEnvio = new Date(quando);
  const quandoValido = !Number.isNaN(dataEnvio.getTime());
  const sck = montarSck(prod, acao || 'disparo', quandoValido ? dataEnvio : agora, 'whatsapp', eu.sigla);
  const linkSugerido = `https://pay.hotmart.com/EXEMPLO?sck=${sck}`;
  const conflitos = quandoValido ? conflitosCom(fichas, prod, dataEnvio.toISOString()) : [];
  const t = aprovados.find((x) => x.id === templateId);
  const quantidade = Number(qtd);
  const recebem = Math.max(0, (quantidade || 0) - sim.suprimidos);

  const faltaParaEnviar = [
    !objetivo.trim() && 'objetivo',
    !filtro.trim() && 'filtro da lista',
    !(quantidade > 0) && 'quantidade',
    !templateId && 'template aprovado',
    !quandoValido && 'data e hora',
    !link.trim() && 'link rastreável',
  ].filter(Boolean) as string[];

  async function salvar(enviar: boolean) {
    if (!objetivo.trim()) { setErro('Escreva o objetivo.'); return; }
    if (enviar && faltaParaEnviar.length) { setErro(`Falta: ${faltaParaEnviar.join(', ')}.`); return; }
    setSalvando(true);
    const msg = await onSalvar({
      objetivo: objetivo.trim(), produto: prod, filtro: filtro.trim(), quantidade: quantidade || 0, suprimidos: sim.suprimidos,
      templateId, numeroEnvio: NUMERO_OFICIAL, agendadoPara: quandoValido ? dataEnvio.toISOString() : amanha10.toISOString(), link: link.trim(),
    }, enviar);
    setSalvando(false);
    if (msg) setErro(msg);
  }

  const resumo = (
    <div className="space-y-3 text-xs">
      <SectionTitle>Resumo</SectionTitle>
      <dl className="space-y-2">
        <LinhaResumo k="Na lista" v={quantidade > 0 ? quantidade.toLocaleString('pt-BR') : '—'} />
        <LinhaResumo k="Suprimidos" v={sim.suprimidos.toLocaleString('pt-BR')} info={INFO_DISPARO.simulador} />
        <LinhaResumo
          k="Recebem"
          info={INFO_DISPARO.recebem}
          v={<span title={`${(quantidade || 0).toLocaleString('pt-BR')} na lista − ${sim.suprimidos.toLocaleString('pt-BR')} suprimidos`} className="font-semibold">{recebem.toLocaleString('pt-BR')}</span>}
        />
        <LinhaResumo
          k="Conflitos 48 h"
          info={INFO_DISPARO.conflitos}
          v={<span className={conflitos.length ? 'font-semibold text-[var(--yellow)]' : ''}>{conflitos.length}</span>}
        />
      </dl>
      <div>
        <div className="text-[var(--fg-3)]">SCK</div>
        <code className="block break-all tabular text-[var(--fg)]">{sck}</code>
      </div>
      <div className="text-[11px] leading-relaxed text-[var(--fg-3)]">
        {faltaParaEnviar.length ? `Falta para enviar: ${faltaParaEnviar.join(', ')}.` : 'Tudo preenchido para enviar.'}
      </div>
    </div>
  );

  return (
    <Drawer
      onClose={onClose}
      width="max-w-3xl"
      title="Nova ficha de disparo"
      subtitle={`Operador: ${eu.nome} · ${gestor ? 'você dispara com a ficha registrada' : 'você dispara depois do ok do Jonathan'}`}
      footer={<>
        {erro && <p role="alert" className="min-w-0 text-xs text-[var(--red)]">{erro}</p>}
        <span className="flex-1" />
        <Button size="sm" variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button size="sm" variant="ghost" disabled={salvando} onClick={() => salvar(false)}>Salvar rascunho</Button>
        <Button size="sm" disabled={salvando} onClick={() => salvar(true)}>
          <Icon name="send" size={13} /> {gestor ? 'Registrar ficha' : 'Enviar para aprovação'}
        </Button>
      </>}
    >
      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_200px]">
        <div className="min-w-0 space-y-5">
          <Secao n={1} titulo="Objetivo e produto">
            <Campo rotulo="Objetivo">
              <Input value={objetivo} onChange={(e) => setObjetivo(e.target.value)} placeholder="Ex.: recuperar quem assistiu a Imersão e não comprou" />
            </Campo>
            <Campo rotulo="Produto">
              <FilterSelect value={prod} onChange={(e) => setProd(e.target.value as ProdutoKey)} className="w-full">
                {PRODUTOS.map((p) => <option key={p.key} value={p.key}>{p.nome} · escada {p.escada}</option>)}
              </FilterSelect>
            </Campo>
          </Secao>

          <Secao n={2} titulo="Lista">
            <Campo rotulo="Filtro da lista" dica="Como a lista foi tirada no CRM. Deduplicada por e-mail ou DDD + últimos 8 dígitos do telefone.">
              <Textarea rows={2} value={filtro} onChange={(e) => setFiltro(e.target.value)} placeholder="Ex.: Fila Imersão SET26 · faixas A e B · status A abordar" />
            </Campo>
            <Campo rotulo="Quantidade">
              <Input type="number" min={1} inputMode="numeric" value={qtd} onChange={(e) => setQtd(e.target.value)} placeholder="0" className="max-w-[160px]" />
            </Campo>
          </Secao>

          <Secao n={3} titulo="Supressões obrigatórias">
            <ul className="space-y-2">
              {SUPRESSOES_OBRIGATORIAS.map((s) => (
                <li key={s} className="flex items-center justify-between gap-3">
                  {/* Obrigatória: marcada e desabilitada, não desmarca. */}
                  <Checkbox checked disabled onChange={() => {}} label={ROTULO_SUPRESSAO[s]} />
                  <span className="text-xs text-[var(--fg-3)] whitespace-nowrap">
                    <span className="tabular text-[var(--fg-2)]">{sim.porMotivo[s].toLocaleString('pt-BR')}</span> · obrigatória
                  </span>
                </li>
              ))}
            </ul>
            <p className="text-xs leading-relaxed text-[var(--fg-2)]">
              Simulador ({produtoDe(prod).nome}): na base de {sim.base.toLocaleString('pt-BR')} contatos, {sim.suprimidos.toLocaleString('pt-BR')} saem pelas
              supressões e {sim.elegiveis.toLocaleString('pt-BR')} podem receber.
              <span className="text-[var(--fg-3)]"> Sem log de disparo na demonstração, a regra de 48 h aparece zerada.</span>
              <InfoIndicador texto={INFO_DISPARO.simulador} className="ml-1" />
            </p>
          </Secao>

          <Secao n={4} titulo="Template e número de envio">
            <Campo rotulo="Template aprovado" dica="Só aparecem templates aprovados. Template novo é aprovado pela Mensageria (Jéssica).">
              <FilterSelect value={templateId} onChange={(e) => setTemplateId(e.target.value)} className="w-full">
                {!aprovados.length && <option value="">Nenhum template aprovado</option>}
                {aprovados.map((x) => <option key={x.id} value={x.id}>{x.nome} · {x.categoria === 'utility' ? 'utilidade' : 'marketing'}</option>)}
              </FilterSelect>
            </Campo>
            {t && <p className="rounded-[var(--r-sm)] border border-[var(--border-faint)] bg-[var(--surface-2)] px-3 py-2 text-[13px] text-[var(--fg-2)]"><TextoTemplate texto={t.texto} /></p>}
            <Campo rotulo="Número de envio">
              <Input value={NUMERO_OFICIAL} readOnly disabled />
            </Campo>
          </Secao>

          <Secao n={5} titulo="Data, hora e operador">
            <Campo rotulo="Agendado para" dica={`Operador: ${eu.nome}`}>
              <Input type="datetime-local" value={quando} onChange={(e) => setQuando(e.target.value)} className="max-w-[240px]" />
            </Campo>
            {conflitos.length > 0 && (
              <Aviso tom="warning" titulo={`Conflito 48 h: ${conflitos.length} ${conflitos.length === 1 ? 'disparo' : 'disparos'} de ${produtoDe(prod).nome}`}>
                A mesma pessoa não recebe disparo da casa em 48 h. Confira a agenda antes de enviar.
              </Aviso>
            )}
          </Secao>

          <Secao n={6} titulo="Link rastreável">
            <Campo rotulo="Ação (entra no SCK)">
              <Input value={acao} onChange={(e) => setAcao(e.target.value)} className="max-w-[240px]" />
            </Campo>
            <div className="flex flex-wrap items-center gap-2 text-xs text-[var(--fg-2)]">
              <span>Sugestão: <code className="tabular text-[var(--fg)] break-all">{sck}</code></span>
              <Button size="sm" variant="ghost" type="button" onClick={() => setLink(linkSugerido)}>Usar sugestão</Button>
            </div>
            <Campo rotulo="Link">
              <Input value={link} onChange={(e) => setLink(e.target.value)} placeholder="https://…?sck=…" />
            </Campo>
          </Secao>
        </div>

        {/* ≥ lg: resumo fixo ao lado do formulário; abaixo dele no celular. */}
        <aside className="lg:sticky lg:top-0 self-start rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
          {resumo}
        </aside>
      </div>
    </Drawer>
  );
}

function LinhaResumo({ k, v, info }: { k: string; v: React.ReactNode; info?: TextoIndicador }) {
  return (
    <div className="flex items-baseline justify-between gap-2">
      <dt className="inline-flex items-center gap-0.5 text-[var(--fg-3)]">{k}{info && <InfoIndicador texto={info} />}</dt>
      <dd className="tabular text-[var(--fg)]">{v}</dd>
    </div>
  );
}
