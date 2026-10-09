'use client';

// Painel do contato dentro da conversa ("Detalhes"; coluna fixa em telas ≥ 2xl). Ações rápidas sem sair da conversa:
// Ligar, Agendar atividade, Lembrete (tarefa com hora: "em 1h" / "amanhã 9h"), Nota, Agendar mensagem.
// Mostra também os negócios abertos, a próxima atividade e as últimas notas. Quem só lê (leitor ou lead de outro)
// vê as informações e o "Ligar" sem registro; as ações de escrita somem.
import { Button, Row, SectionTitle } from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { ICONE_ATIVIDADE, ROTULO_ATUA, ROTULO_PERFIL } from '../../domain/catalogo';
import { fmtTelefone } from '../../domain/regras';
import type { Contato, EtapaFunil, Negocio } from '../../domain/types';
import type { TravaMover } from '../../domain/travas';
import { BotaoLigar } from '../BotaoLigar';
import { Dono } from '../comum';
import { CardNegocio } from '../funil/CardNegocio';
import { repo, useDados } from '../repositorio';

export type AcaoRapida = 'atividade' | 'lembrete' | 'nota' | 'mensagem';

export function PainelContato({ c, negocios, agora, nomeDe, etapasDe, leituraDe, travaPara, onAbrirNegocio, onAgendar, onMover, onCopiarTelefone, onAbrirFicha,
  podeEscrever, podeMensagem, onAcao, flash }: {
  c: Contato; negocios: Negocio[]; agora: Date; nomeDe: (id: string | null) => string;
  etapasDe: (n: Negocio) => EtapaFunil[];
  leituraDe: (n: Negocio) => string | null;
  travaPara: (n: Negocio, etapaId: string) => TravaMover;
  onAbrirNegocio: (id: string) => void; onAgendar: (n: Negocio) => void; onMover: (n: Negocio, etapaId: string) => void;
  onCopiarTelefone: (tel: string) => void; onAbrirFicha: () => void;
  /** Pode registrar atividade/nota para este contato (dono, dono de negócio ou gestor; leitor não). */
  podeEscrever: boolean;
  /** Pode agendar mensagem (escreve + número disponível + sem opt-out). */
  podeMensagem: boolean;
  onAcao: (a: AcaoRapida) => void;
  flash: (s: string) => void;
}) {
  // Últimas notas da pessoa (linha do tempo, só as notas). Próxima atividade: a mais cedo entre os negócios abertos.
  const { dados: eventos } = useDados(() => repo.eventos(c.id), [c.id]);
  const notas = (eventos ?? []).filter((e) => e.tipo === 'nota').sort((a, b) => b.em.localeCompare(a.em)).slice(0, 3);
  const proxima = negocios.map((n) => n.proximaAtividade).filter((a): a is NonNullable<Negocio['proximaAtividade']> => !!a)
    .sort((a, b) => a.venceEm.localeCompare(b.venceEm))[0] ?? null;
  const atrasada = !!proxima && new Date(proxima.venceEm).getTime() < agora.getTime();

  return (
    <div className="space-y-6">
      <section aria-label="Ações rápidas">
        <div className="flex flex-wrap gap-1.5">
          <BotaoLigar alvo={{ contatoId: c.id, nome: c.nome, telefone: c.telefone, negocioId: negocios[0]?.id ?? null }} podeRegistrar={podeEscrever} flash={flash}
                      className="border border-[var(--border)]" />
          {podeEscrever && (
            <>
              <Button size="sm" variant="ghost" className="border border-[var(--border)]" onClick={() => onAcao('atividade')} title="Agendar atividade">
                <Icon name="calendar" size={14} /> Atividade
              </Button>
              <Button size="sm" variant="ghost" className="border border-[var(--border)]" onClick={() => onAcao('lembrete')} title="Lembrete (tarefa com hora)">
                <Icon name="bell" size={14} /> Lembrete
              </Button>
              <Button size="sm" variant="ghost" className="border border-[var(--border)]" onClick={() => onAcao('nota')} title="Adicionar nota interna">
                <Icon name="notebook" size={14} /> Nota
              </Button>
            </>
          )}
          {podeMensagem && (
            <Button size="sm" variant="ghost" className="border border-[var(--border)]" onClick={() => onAcao('mensagem')} title="Agendar mensagem no WhatsApp">
              <Icon name="clock" size={14} /> Agendar mensagem
            </Button>
          )}
        </div>
      </section>

      <section>
        <SectionTitle right={<Button size="sm" variant="link" onClick={onAbrirFicha}>Ver ficha</Button>}>Contato</SectionTitle>
        <div>
          <Row k="Telefone" v={fmtTelefone(c.telefone)} />
          <Row k="E-mail" v={c.email ?? '—'} />
          <Row k="Cidade" v={c.cidade ? `${c.cidade}/${c.uf ?? ''}` : '—'} />
          <Row k="Perfil" v={c.perfil ? ROTULO_PERFIL[c.perfil] : '—'} />
          <Row k="Holding" v={c.atuaComHolding ? ROTULO_ATUA[c.atuaComHolding] : '—'} />
          <Row k="Dono" v={<Dono id={c.donoId} nomeDe={nomeDe} />} />
        </div>
        {c.tags.length > 0 && (
          <p className="mt-2 text-xs text-[var(--fg-3)]">
            <span className="sr-only">Tags: </span>{c.tags.join(' · ')}
          </p>
        )}
      </section>

      <section>
        <SectionTitle>Próxima atividade</SectionTitle>
        {proxima ? (
          <div className={`flex items-start gap-2 text-sm ${atrasada ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>
            <Icon name={ICONE_ATIVIDADE[proxima.tipo]} size={14} className="mt-0.5 shrink-0" />
            <span className="min-w-0">
              <span className="block truncate">{proxima.titulo}</span>
              <span className="block text-xs text-[var(--fg-3)]">{atrasada ? 'Atrasada · ' : ''}{fmtDataHora(proxima.venceEm)}</span>
            </span>
          </div>
        ) : (
          <p className="text-xs text-[var(--fg-3)]">Sem próxima atividade. Toda conversa termina com próximo passo e data.</p>
        )}
      </section>

      <section>
        <SectionTitle>{negocios.length > 1 ? `Negócios abertos (${negocios.length})` : 'Negócio aberto'}</SectionTitle>
        {negocios.length === 0 ? (
          <div className="text-xs text-[var(--fg-3)] leading-relaxed">
            Nenhum negócio aberto. Se não está no CRM, não existe.
            <Button size="sm" variant="link" className="ml-1 !text-xs" onClick={onAbrirFicha}>Abrir pela ficha</Button>
          </div>
        ) : (
          <div className="space-y-2">
            {negocios.map((n) => (
              <div key={n.id}>
                <CardNegocio
                  n={n}
                  c={c}
                  agora={agora}
                  nomeDe={nomeDe}
                  etapas={etapasDe(n)}
                  leitura={leituraDe(n)}
                  travaPara={(etapaId) => travaPara(n, etapaId)}
                  onAbrir={() => onAbrirNegocio(n.id)}
                  onAgendar={() => onAgendar(n)}
                  onMover={(etapaId) => onMover(n, etapaId)}
                  onCopiarTelefone={onCopiarTelefone}
                  arrastavel={false}
                />
                <div className="mt-1 flex items-center justify-between gap-2 text-[11px] text-[var(--fg-3)]">
                  <span className="truncate">{n.etapaNome}</span>
                  <Button size="sm" variant="link" className="!text-xs" onClick={() => onAbrirNegocio(n.id)}>Abrir</Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <section>
        <SectionTitle>Últimas notas</SectionTitle>
        {notas.length === 0 ? (
          <p className="text-xs text-[var(--fg-3)]">{eventos ? 'Nenhuma nota ainda.' : 'Carregando…'}</p>
        ) : (
          <ul className="space-y-2">
            {notas.map((e) => (
              <li key={e.id} className="text-sm">
                <p className="text-[var(--fg)] whitespace-pre-wrap break-words line-clamp-4">{e.detalhe ?? e.titulo}</p>
                <p className="text-[11px] text-[var(--fg-3)]">{e.autorId ? `${nomeDe(e.autorId)} · ` : ''}{fmtDataHora(e.em)}</p>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
