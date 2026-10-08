'use client';

// Abas "Dados" (cadastro, UTM de origem do cadastro, tags, possíveis duplicados) e "Conversa" (prévia + atalho).
import { useState } from 'react';
import { Button, Row, SectionTitle, Skeleton } from '@/shared/ui/components';
import { fmtData, fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_ATUA, ROTULO_PERFIL } from '../../domain/catalogo';
import { faixaDoScore, fmtTelefone } from '../../domain/regras';
import type { Contato } from '../../domain/types';
import { BotaoConversa, Dono, EstadoErro, Vazio } from '../comum';
import { InfoIndicador } from '../InfoIndicador';
import { INFO_FILA } from '../recuperacao/indicadores';
import { repo, useAtualizacaoPeriodica, useDados } from '../repositorio';
import { utmEmLinha } from './regras-contatos';
import { MidiaMensagem } from '../conversas/MidiaMensagem';
import { legendaDaMensagem } from '../../domain/midia';
import { ComoEntrou } from './ComoEntrou';
import { BotaoGravarAudio } from '../conversas/GravarAudio';
import { janelaRestante } from '../conversas/regras-conversas';
import { semNome } from '../../domain/editar-contato';
import { FormEdicaoContato } from './EdicaoContato';
import { EditorTags } from './EditorTags';

/** Estado do modo edição, dono da ficha (o cabeçalho também abre pelo atalho "Adicionar nome"). */
export interface EdicaoFicha {
  /** null = pode editar; texto = motivo da trava (mostrado no lugar do botão). */
  motivo: string | null;
  editando: boolean;
  setEditando: (v: boolean) => void;
  onSalvo: (msg: string) => void;
}

export function AbaDados({ c, duplicados, nomeDe, onAbrirContato, edicao }: {
  c: Contato;
  duplicados: Contato[];
  nomeDe: (id: string | null) => string;
  onAbrirContato?: (id: string) => void;
  edicao?: EdicaoFicha;
}) {
  const [utmAberta, setUtmAberta] = useState(false);
  const faixa = c.score != null ? faixaDoScore(c.score) : null;
  const temDetalheUtm = !!(c.utm.content || c.utm.sck || c.utm.medium || c.utm.campaign);
  return (
    <div className="grid gap-6 md:grid-cols-2">
      <section className="min-w-0">
        <SectionTitle
          right={edicao && !edicao.editando && !edicao.motivo ? (
            <Button size="sm" variant="ghost" onClick={() => edicao.setEditando(true)}>
              <Icon name="pencil" size={14} /> Editar
            </Button>
          ) : undefined}
        >
          Dados
        </SectionTitle>
        {edicao?.editando && !edicao.motivo ? (
          <FormEdicaoContato
            c={c}
            onCancelar={() => edicao.setEditando(false)}
            onSalvo={(msg) => { edicao.setEditando(false); edicao.onSalvo(msg); }}
          />
        ) : (
          <>
            {edicao?.motivo && <p className="mb-2 text-xs text-[var(--fg-3)]">Edição: {edicao.motivo}</p>}
            {semNome(c.nome) && edicao && !edicao.motivo && (
              <Row k="Nome" v={<Button size="sm" variant="link" onClick={() => edicao.setEditando(true)}>Adicionar nome</Button>} />
            )}
            <Row k="Telefone" v={<span className="tabular select-all">{fmtTelefone(c.telefone)}</span>} />
            <Row k="E-mail" v={c.email ?? '—'} />
            <Row k="Cidade" v={c.cidade ? `${c.cidade}${c.uf ? ` · ${c.uf}` : ''}` : '—'} />
            <Row k="Perfil" v={c.perfil ? ROTULO_PERFIL[c.perfil] : '—'} />
            <Row k="Holding" v={c.atuaComHolding ? ROTULO_ATUA[c.atuaComHolding] : '—'} />
            {c.empresa && <Row k="Empresa" v={c.empresa} />}
            {c.observacao && <Row k="Observação" v={<span className="whitespace-pre-wrap">{c.observacao}</span>} />}
          </>
        )}
        <Row k="Dono" v={<Dono id={c.donoId} nomeDe={nomeDe} />} />
        <Row k="Score" v={faixa ? (
          <span className="inline-flex items-center gap-1">
            <span className="tabular">{c.score} <span className="text-xs text-[var(--fg-3)]">faixa {faixa}</span></span>
            <InfoIndicador texto={INFO_FILA.faixas} />
          </span>
        ) : '—'} />
        <Row k="Cadastro" v={<span className="tabular">{fmtData(c.criadoEm)}</span>} />
      </section>

      <div className="min-w-0 space-y-6">
        <ComoEntrou contatoId={c.id} />
        <section>
          <SectionTitle
            right={temDetalheUtm ? (
              <Button size="sm" variant="link" aria-expanded={utmAberta} onClick={() => setUtmAberta((v) => !v)}>
                {utmAberta ? 'ocultar detalhes' : 'ver detalhes'}
              </Button>
            ) : undefined}
          >
            Origem do cadastro
          </SectionTitle>
          <p className="break-words text-sm text-[var(--fg-2)]">{utmEmLinha(c.utm)}</p>
          <p className="mt-1 text-xs text-[var(--fg-3)]">Primeira entrada. Cada lançamento tem a própria origem na aba Jornada.</p>
          {utmAberta && (
            <div className="mt-2">
              <Row k="Source" v={c.utm.source ?? '—'} />
              <Row k="Medium" v={c.utm.medium ?? '—'} />
              <Row k="Campaign" v={c.utm.campaign ?? '—'} />
              <Row k="Content" v={c.utm.content ?? '—'} />
              <Row k="SCK" v={c.utm.sck ?? '—'} />
            </div>
          )}
        </section>

        <section>
          <SectionTitle>Tags</SectionTitle>
          {edicao && !edicao.motivo ? (
            <EditorTags contatoId={c.id} tags={c.tags} onSalvo={edicao.onSalvo} />
          ) : (
            <p className="text-sm text-[var(--fg-2)]">{c.tags.length ? c.tags.join(', ') : <span className="text-[var(--fg-3)]">Sem tags.</span>}</p>
          )}
        </section>

        {duplicados.length > 0 && (
          <section>
            <SectionTitle right={<span className="text-[11px] text-[var(--fg-3)] tabular">{duplicados.length}</span>}>
              Possíveis duplicados
            </SectionTitle>
            <p className="mb-2 text-xs text-[var(--fg-3)]">Mesmo final de telefone. Confira antes de abordar.</p>
            <ul className="divide-y divide-[var(--border-faint)]">
              {duplicados.map((d) => (
                <li key={d.id} className="flex items-center justify-between gap-3 py-2">
                  <div className="min-w-0">
                    <div className="truncate text-sm text-[var(--fg)]">{d.nome}</div>
                    <div className="truncate text-xs text-[var(--fg-3)]">
                      {d.email ?? 'sem e-mail'} · {fmtTelefone(d.telefone)} · {nomeDe(d.donoId)}
                    </div>
                  </div>
                  {onAbrirContato && <Button size="sm" variant="ghost" onClick={() => onAbrirContato(d.id)}>Abrir ficha</Button>}
                </li>
              ))}
            </ul>
          </section>
        )}
      </div>
    </div>
  );
}

/** Últimas mensagens e o atalho para a caixa de Conversas (onde se responde). */
export function AbaConversa({ c, nomeDe, flash, podeEscrever }: {
  c: Contato; nomeDe: (id: string | null) => string; flash?: (m: string) => void;
  /** `podeEscreverContato` (espelho de crm.pode_escrever_pessoa): sem ele, nem oferece o áudio. */
  podeEscrever: boolean;
}) {
  const ms = useDados(() => repo.mensagens(c.id), [c.id]);
  // Aba aberta = conversa à vista: atualiza sozinha (mensagem nova, mídia, status).
  useAtualizacaoPeriodica(ms.recarregar, 'conversaAberta', !c.optOut && !!c.telefone);
  if (c.optOut) {
    return <Vazio titulo="Sem conversa" hint="Pediu para não receber contato: ninguém aborda esta pessoa." icone="lock" />;
  }
  if (!c.telefone) {
    return <Vazio titulo="Sem telefone" hint="Cadastre o telefone para conversar pelo WhatsApp." icone="phone" />;
  }
  if (ms.erro && !ms.dados) return <EstadoErro mensagem={ms.erro} onTentar={ms.recarregar} />;
  if (!ms.dados) {
    return <div className="space-y-3" aria-busy="true">{[0, 1, 2].map((i) => <Skeleton key={i} h={14} w={`${80 - i * 10}%`} />)}</div>;
  }
  const ultimas = [...ms.dados].sort((a, b) => b.em.localeCompare(a.em)).slice(0, 5);
  // janela de 24 h pela última mensagem recebida: com ela aberta dá para mandar áudio daqui (o banco confere de novo)
  const ultimaEntrada = ms.dados.filter((m) => m.direcao === 'entrada' && m.canal !== 'nota').reduce<string | null>((x, m) => (!x || m.em > x ? m.em : x), null);
  const janela = ultimaEntrada ? janelaRestante(new Date(new Date(ultimaEntrada).getTime() + 86_400_000).toISOString(), new Date()) : null;
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-[var(--fg-2)]">
          {ms.dados.length
            ? `${ms.dados.length} mensage${ms.dados.length > 1 ? 'ns' : 'm'} no histórico. Responda pela caixa de Conversas.`
            : 'Nenhuma mensagem ainda. Comece pela caixa de Conversas.'}
        </p>
        <div className="flex shrink-0 items-center gap-2">
          {janela && flash && podeEscrever && <BotaoGravarAudio contatoId={c.id} nomeContato={c.nome.split(' ')[0] || c.nome} flash={flash} />}
          <BotaoConversa contatoId={c.id} />
        </div>
      </div>
      {ultimas.length > 0 && (
        <ul className="space-y-2">
          {ultimas.map((m) => (
            <li
              key={m.id}
              className={`rounded-[var(--r-md)] border border-[var(--border-faint)] px-3 py-2 ${m.direcao === 'entrada' ? 'bg-[var(--surface-2)]' : 'bg-[var(--surface-3)]'}`}
            >
              <div className="flex items-center justify-between gap-3 text-xs text-[var(--fg-3)]">
                <span className="inline-flex items-center gap-1">
                  <Icon name={m.direcao === 'entrada' ? 'arrow-left' : 'arrow-right'} size={12} />
                  {m.direcao === 'entrada' ? c.nome.split(' ')[0] : m.canal === 'nota' ? 'Nota interna' : nomeDe(m.autorId)}
                </span>
                <span className="tabular">{fmtDataHora(m.em)}</span>
              </div>
              <div className="mt-1"><MidiaMensagem m={m} compacto /></div>
              {legendaDaMensagem(m) && <p className="mt-1 line-clamp-3 whitespace-pre-wrap text-sm text-[var(--fg)]">{legendaDaMensagem(m)}</p>}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
