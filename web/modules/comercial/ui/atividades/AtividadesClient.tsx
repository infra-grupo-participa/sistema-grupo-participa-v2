'use client';

// Agenda do vendedor: o que fazer hoje, o que atrasou, o que vem e o que já foi feito.
// Toda atividade mostra contato, produto e etapa do negócio; clicar no nome abre a ficha do negócio.
// Lead que não é seu não se toca: só o dono (ou o gestor) conclui a atividade.
// Concluir sempre emenda no "Agendar próximo passo" (nenhum negócio aberto sem próxima atividade).
import { useMemo, useState } from 'react';
import {
  Button, Card, Drawer, EmptyState, FilterSelect, SectionTitle, Skeleton, Tabs, Toast, Toolbar, useFlash,
} from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { CADENCIA, ICONE_ATIVIDADE, ROTULO_ATIVIDADE, produto as produtoDe, rotuloMotivo } from '../../domain/catalogo';
import { atividadeAtrasada } from '../../domain/regras';
import type { Atividade, Negocio, TipoAtividade } from '../../domain/types';
import { EstadoErro, FaixaNumeros, PaginaComercial, useAbaHash, useEquipe } from '../comum';
import { NegocioDrawer } from '../NegocioDrawer';
import { repo, useAgora, useDados } from '../repositorio';
import { negocioDoContato } from '../inicio/painel';
import { INFO_AGENDA } from './indicadores';
import { ABAS_AGENDA, agruparAgenda, contadoresAgenda, naAba, type AbaAgenda } from './agenda';
import { LinhaAgenda } from './LinhaAgenda';
import { ModalAgendar, useConcluirComProximo } from './ProximoPasso';

const TIPOS: TipoAtividade[] = ['whatsapp', 'ligacao', 'email', 'reuniao', 'tarefa'];

const ROTULO_ABA: Record<AbaAgenda, string> = {
  hoje: 'Hoje', atrasadas: 'Atrasadas', proximas: 'Próximas', concluidas: 'Concluídas',
};

const VAZIO: Record<AbaAgenda, { title: string; hint: string }> = {
  hoje: { title: 'Nada para hoje', hint: 'Confira se todo negócio aberto tem próxima atividade com data.' },
  atrasadas: { title: 'Nenhuma atividade atrasada', hint: 'CRM em dia. Mantenha assim até as 18h45.' },
  proximas: { title: 'Nada agendado para os próximos dias', hint: 'Quem define o próximo passo é o vendedor, não o lead.' },
  concluidas: { title: 'Nenhuma atividade concluída', hint: 'Se não está no CRM, não existe: registre o resultado de cada toque.' },
};

export function AtividadesClient() {
  const agora = useAgora();
  const { toast, flash } = useFlash();
  const { sessao, vendedores, nomeDe, gestor } = useEquipe();
  const atvQ = useDados(() => repo.atividades());
  const negQ = useDados(() => repo.negocios());
  const conQ = useDados(() => repo.contatos());
  // Cadastro de motivos de perda (fábrica + criados pelo gestor): rótulo do motivo nos negócios perdidos.
  const { dados: motivos } = useDados(() => repo.motivosPerda());
  const atividades = atvQ.dados;
  const negocios = negQ.dados;
  const contatos = conQ.dados;
  const erro = atvQ.erro || negQ.erro || conQ.erro;
  const recarregar = () => { atvQ.recarregar(); negQ.recarregar(); conQ.recarregar(); };

  const [aba, setAba] = useAbaHash<AbaAgenda>(ABAS_AGENDA, 'hoje');
  const [tipo, setTipo] = useState<TipoAtividade | 'todos'>('todos');
  // Escolha de dono vale para a sessão em que foi feita; trocar o "ver como" volta ao padrão do papel.
  const [escolhaDono, setEscolhaDono] = useState<{ sessao: string; valor: string } | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [verCadencia, setVerCadencia] = useState(false);
  const [nova, setNova] = useState(false);
  const fluxo = useConcluirComProximo(flash);

  const eu = sessao?.vendedorId ?? null;
  const dono = escolhaDono && escolhaDono.sessao === eu ? escolhaDono.valor : gestor ? 'todos' : 'meus';
  const padraoDono = gestor ? 'todos' : 'meus';

  const contatoPorId = useMemo(() => new Map((contatos ?? []).map((c) => [c.id, c])), [contatos]);
  const negocioPorId = useMemo(() => new Map((negocios ?? []).map((n) => [n.id, n])), [negocios]);

  // Filtro de dono vale para tudo (contadores inclusive); o de tipo só para a lista.
  const doDono = useMemo(() => (atividades ?? []).filter((a) => {
    if (dono === 'todos') return true;
    if (dono === 'meus') return a.donoId === eu;
    return a.donoId === dono;
  }), [atividades, dono, eu]);

  const filtradas = useMemo(() => doDono.filter((a) => tipo === 'todos' || a.tipo === tipo), [doDono, tipo]);
  const grupos = useMemo(() => agruparAgenda(filtradas, aba, agora), [filtradas, aba, agora]);
  const k = contadoresAgenda(doDono, agora);
  const nAba = (a: AbaAgenda) => filtradas.filter((x) => naAba(x, a, agora)).length;
  const filtrosAtivos = tipo !== 'todos' || dono !== padraoDono;

  const negocioDe = (a: Atividade): Negocio | undefined =>
    (a.negocioId ? negocioPorId.get(a.negocioId) : undefined) ?? negocioDoContato(negocios ?? [], a.contatoId, a.donoId) ?? undefined;

  // Negócios abertos que a pessoa pode agendar (os dela; o gestor, todos).
  const opcoesNova = useMemo(() => (negocios ?? [])
    .filter((n) => n.status === 'aberto' && (gestor || n.donoId === eu))
    .map((n) => ({ id: n.id, contatoId: n.contatoId, rotulo: `${contatoPorId.get(n.contatoId)?.nome ?? '—'} · ${produtoDe(n.produto).nome} · ${n.etapaNome}` }))
    .sort((a, b) => a.rotulo.localeCompare(b.rotulo, 'pt-BR')), [negocios, gestor, eu, contatoPorId]);

  const pronto = !!(atividades && negocios && contatos && sessao);

  return (
    <PaginaComercial
      titulo="Atividades"
      subtitulo="Agenda de toques: o que fazer hoje, o que atrasou e o que vem."
      acoes={<>
        <Button size="sm" variant="ghost" onClick={() => setVerCadencia(true)}><Icon name="list-checks" size={14} /> Cadência padrão</Button>
        <Button size="sm" onClick={() => setNova(true)} disabled={!pronto}><Icon name="plus" size={14} /> Nova atividade</Button>
      </>}
    >
      {erro && !pronto ? (
        <EstadoErro mensagem={erro} onTentar={recarregar} />
      ) : !pronto ? (
        <EsqueletoAgenda />
      ) : (
        <div className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <Toolbar>
              <FilterSelect value={dono} onChange={(e) => setEscolhaDono({ sessao: eu ?? '', valor: e.target.value })} aria-label="Dono">
                <option value="meus">Minhas atividades</option>
                <option value="todos">Todo o time</option>
                {vendedores.filter((v) => v.ativo).map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
              </FilterSelect>
              <FilterSelect value={tipo} onChange={(e) => setTipo(e.target.value as TipoAtividade | 'todos')} aria-label="Tipo">
                <option value="todos">Todos os tipos</option>
                {TIPOS.map((t) => <option key={t} value={t}>{ROTULO_ATIVIDADE[t]}</option>)}
              </FilterSelect>
            </Toolbar>
            <FaixaNumeros
              discreta
              rotulo="Agenda de hoje"
              itens={[
                { rotulo: 'Para hoje', valor: k.hoje, info: INFO_AGENDA.paraHoje, title: 'Ver as de hoje', onClick: () => setAba('hoje') },
                {
                  rotulo: 'Atrasadas', valor: k.atrasadas, metrica: 'atrasadas', alerta: k.atrasadas > 0,
                  title: 'Ver as atrasadas', onClick: () => setAba('atrasadas'),
                },
                { rotulo: 'Concluídas hoje', valor: k.concluidasHoje, info: INFO_AGENDA.concluidasHoje },
                { rotulo: 'Ligações hoje', valor: <>{k.ligacoesHoje}<span className="font-normal text-[var(--fg-3)]"> de {k.ligacoesAgendadasHoje}</span></>, info: INFO_AGENDA.ligacoesHoje },
              ]}
            />
          </div>

          <div>
            <Tabs
              tabs={ABAS_AGENDA.map((a) => ({
                k: a,
                // Contagem no rótulo; o marcador de pendência (n) só em Atrasadas.
                l: a === 'concluidas' || a === 'atrasadas' ? ROTULO_ABA[a] : `${ROTULO_ABA[a]} (${nAba(a)})`,
                n: a === 'atrasadas' ? nAba(a) : undefined,
              }))}
              active={aba}
              onChange={(x) => setAba(x as AbaAgenda)}
              label="Período da agenda"
            />

            {grupos.length === 0 ? (
              <Card className="px-5">
                <EmptyState title={filtrosAtivos && tipo !== 'todos' ? 'Nada com esse filtro' : VAZIO[aba].title} hint={VAZIO[aba].hint} icon="list-checks" />
                <div className="-mt-6 pb-8 flex justify-center gap-2">
                  {filtrosAtivos && (
                    <Button size="sm" variant="ghost" onClick={() => { setTipo('todos'); setEscolhaDono(null); }}>Limpar filtros</Button>
                  )}
                  {(aba === 'hoje' || aba === 'proximas') && (
                    <Button size="sm" variant="ghost" onClick={() => setNova(true)}><Icon name="plus" size={14} /> Agendar atividade</Button>
                  )}
                </div>
              </Card>
            ) : (
              <div className="space-y-5">
                {grupos.map((g) => (
                  <section key={g.key} aria-label={g.titulo}>
                    <SectionTitle right={<span className={`text-[11px] tabular ${g.atrasado ? 'text-[var(--red)] font-semibold' : 'text-[var(--fg-3)]'}`}>{g.itens.length}</span>}>
                      {g.titulo}
                    </SectionTitle>
                    <Card as="ul" className="divide-y divide-[var(--border-faint)]">
                      {g.itens.map((a) => {
                        const n = negocioDe(a);
                        const podeMexer = a.donoId === eu || gestor;
                        return (
                          <LinhaAgenda
                            key={a.id}
                            a={a} c={contatoPorId.get(a.contatoId)} n={n}
                            dono={dono === 'meus' ? null : nomeDe(a.donoId)}
                            motivoPerda={n?.status === 'perdido' ? rotuloMotivo(n.motivoPerda, motivos ?? undefined) : null}
                            atrasada={atividadeAtrasada(a, agora)}
                            agora={agora}
                            onAbrir={n ? () => setAberto(n.id) : undefined}
                            onConcluir={!a.concluidaEm && podeMexer ? (res) => fluxo.concluir(a, res, n) : undefined}
                          />
                        );
                      })}
                    </Card>
                  </section>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {verCadencia && <CadenciaPadrao motivoEsgotado={rotuloMotivo('tentativas_esgotadas', motivos ?? undefined)} onClose={() => setVerCadencia(false)} />}
      {nova && (
        <ModalAgendar
          titulo="Nova atividade"
          intro="Quem define o próximo passo é o vendedor, não o lead."
          opcoes={opcoesNova}
          onClose={() => setNova(false)}
          onAgendado={(msg) => { setNova(false); flash(msg); }}
        />
      )}
      {fluxo.modais}
      {aberto && <NegocioDrawer negocioId={aberto} onClose={() => setAberto(null)} />}
      <Toast>{toast}</Toast>
    </PaginaComercial>
  );
}

/** Esqueleto no formato da agenda (toolbar, abas e linhas). */
function EsqueletoAgenda() {
  return (
    <div className="space-y-4" aria-busy="true" aria-label="Carregando a agenda">
      <div className="flex gap-2"><Skeleton w={180} h={32} /><Skeleton w={150} h={32} /></div>
      <Skeleton w={360} h={28} />
      <Card className="divide-y divide-[var(--border-faint)]">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="flex items-center gap-3 px-3 py-3">
            <Skeleton w={16} h={16} />
            <div className="flex-1 space-y-1.5"><Skeleton w="45%" h={12} /><Skeleton w="30%" h={10} /></div>
            <Skeleton w={40} h={10} />
          </div>
        ))}
      </Card>
    </div>
  );
}

/** Cadência padrão depois do primeiro contato sem resposta (playbook, seção 9). Referência sob demanda. */
function CadenciaPadrao({ motivoEsgotado, onClose }: { motivoEsgotado: string; onClose: () => void }) {
  return (
    <Drawer onClose={onClose} title="Cadência padrão" subtitle="Primeiro contato sem resposta: siga os toques do dia." width="max-w-md">
      <ol className="divide-y divide-[var(--border-faint)]">
        {CADENCIA.map((d) => (
          <li key={d.dia} className="flex gap-3 py-3">
            <span className="w-12 shrink-0 text-xs font-semibold tabular text-[var(--fg-3)]">Dia {d.dia}</span>
            <ul className="space-y-1 min-w-0">
              {d.toques.map((t, i) => (
                <li key={i} className="flex items-center gap-2 text-sm text-[var(--fg-2)]">
                  <Icon name={ICONE_ATIVIDADE[t.tipo]} size={14} className="text-[var(--fg-3)] shrink-0" />
                  <span className="sr-only">{ROTULO_ATIVIDADE[t.tipo]}:</span>
                  {t.titulo}
                </li>
              ))}
            </ul>
          </li>
        ))}
      </ol>
      <p className="mt-4 text-xs leading-relaxed text-[var(--fg-3)]">
        <strong className="font-semibold text-[var(--fg-2)]">Depois da proposta:</strong> até 5 tentativas cruzando ligação e WhatsApp,
        intervalo de 1 a 2 dias. Depois, encerramento (perdido com motivo &ldquo;{motivoEsgotado}&rdquo;).
      </p>
    </Drawer>
  );
}
