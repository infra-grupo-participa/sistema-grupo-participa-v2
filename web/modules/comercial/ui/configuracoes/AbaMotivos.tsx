'use client';

// Aba #motivos: cadastro de motivos de perda. Os 9 de fábrica (playbook) só mudam nota e ativo;
// os personalizados o gestor cria, edita e desativa. Vendedor vê a lista em modo leitura.
import { useState } from 'react';
import { Badge, Button, Card, Checkbox, Input, Modal, Textarea } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { MotivoPerdaConfig } from '../../domain/types';
import { Aviso, Campo, Carregando, EsqueletoLista, FaixaNumeros, NotaRodape, Vazio } from '../comum';
import { avisarMudanca, repo, useDados } from '../repositorio';
import {
  LIMITE_NOME_MOTIVO, alternarAtivo, ordenarMotivos, previaChave, rascunhoMotivo, resumoMotivos, validarMotivo, type RascunhoMotivo,
} from './motivos';

export function AbaMotivos({ gestor, flash }: { gestor: boolean; flash: (m: string) => void }) {
  const r = useDados(() => repo.motivosPerda());
  // undefined = modal fechado; null = motivo novo.
  const [editando, setEditando] = useState<MotivoPerdaConfig | null | undefined>(undefined);
  const [alternando, setAlternando] = useState<string | null>(null);

  async function alternar(m: MotivoPerdaConfig) {
    setAlternando(m.key);
    const res = await repo.salvarMotivoPerda(alternarAtivo(m));
    setAlternando(null);
    if (res.ok) { flash(m.ativo ? 'Motivo desativado.' : 'Motivo reativado.'); avisarMudanca(); } else flash(res.msg ?? 'Não foi possível salvar.');
  }

  return (
    <div className="space-y-4">
      <Carregando dados={r.dados} erro={r.erro} onTentar={() => { void r.recarregar(); }} esqueleto={<EsqueletoLista linhas={6} avatar={false} />}>
        {(cadastro) => {
          const lista = ordenarMotivos(cadastro);
          const res = resumoMotivos(cadastro);
          return (
            <>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <FaixaNumeros itens={[
                  {
                    rotulo: 'Ativos', valor: res.ativos,
                    info: { nome: 'Motivos ativos', oQueE: 'Motivos que o vendedor pode escolher ao marcar um negócio como perdido.', comoConta: 'Fábrica + personalizados, sem os desativados.' },
                  },
                  {
                    rotulo: 'Personalizados', valor: res.personalizados,
                    info: { nome: 'Motivos personalizados', oQueE: 'Motivos criados pelo gestor além dos 9 do playbook.', paraQue: 'Se um personalizado vira o mais usado, vale revisar o playbook.' },
                  },
                  {
                    rotulo: 'Desativados', valor: res.desativados,
                    info: { nome: 'Motivos desativados', oQueE: 'Motivos fora da lista de escolha.', comoConta: 'Perdidos antigos continuam com o motivo e aparecem nos relatórios.' },
                  },
                ]} />
                {gestor && <Button size="sm" onClick={() => setEditando(null)}><Icon name="plus" size={14} /> Novo motivo</Button>}
              </div>

              {!gestor && (
                <Aviso tom="neutral" icone="lock">Só o gestor do Comercial cria, edita ou desativa motivos.</Aviso>
              )}

              {lista.length ? (
                <ul className="space-y-2">
                  {lista.map((m) => (
                    <LinhaMotivo
                      key={m.key} m={m} gestor={gestor} ocupado={alternando === m.key}
                      onEditar={() => setEditando(m)} onAlternar={() => { void alternar(m); }}
                    />
                  ))}
                </ul>
              ) : (
                <Card><Vazio titulo="Nenhum motivo cadastrado" icone="list-checks" /></Card>
              )}
              <NotaRodape>
                Lista única: motivo fora do cadastro não existe. Nada se apaga: desativar tira da escolha, mas o histórico e os relatórios continuam com o motivo.
              </NotaRodape>

              {editando !== undefined && (
                <ModalMotivo
                  editando={editando}
                  cadastro={cadastro}
                  onFechar={() => setEditando(undefined)}
                  onSalvo={(msg) => { setEditando(undefined); flash(msg); avisarMudanca(); }}
                />
              )}
            </>
          );
        }}
      </Carregando>
    </div>
  );
}

function LinhaMotivo({ m, gestor, ocupado, onEditar, onAlternar }: {
  m: MotivoPerdaConfig; gestor: boolean; ocupado: boolean; onEditar: () => void; onAlternar: () => void;
}) {
  return (
    <li>
      <Card className={`p-3 flex flex-wrap items-start gap-x-4 gap-y-2 ${m.ativo ? '' : 'opacity-70'}`}>
        <div className="min-w-0 flex-1 basis-64 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-medium text-[var(--fg)]">{m.label}</span>
            {m.sistema && (
              <span className="rounded-[var(--r-sm)] border border-[var(--border)] px-1.5 text-[11px] text-[var(--fg-3)]" title="Motivo de fábrica do playbook: só a nota e o ativo mudam">
                playbook
              </span>
            )}
            {!m.ativo && <Badge tone="neutral">Desativado</Badge>}
          </div>
          <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs text-[var(--fg-2)]">
            {m.reativa && <Efeito icone="refresh">Volta para reativação</Efeito>}
            {m.bloqueia && <Efeito icone="lock">Vai para a lista de bloqueio</Efeito>}
            {m.alertaGestor && <Efeito icone="alert">Avisa o gestor no mesmo dia</Efeito>}
            {!m.reativa && !m.bloqueia && !m.alertaGestor && <span className="text-[var(--fg-3)]">Encerra sem efeito extra</span>}
          </div>
          {m.nota && <p className="text-xs text-[var(--fg-3)] leading-relaxed">{m.nota}</p>}
        </div>
        {gestor && (
          <div className="flex shrink-0 items-center gap-2">
            <Button size="sm" variant="ghost" onClick={onEditar} aria-label={`Editar ${m.label}`}><Icon name="pencil" size={14} /> Editar</Button>
            <Button size="sm" variant="ghost" disabled={ocupado} onClick={onAlternar} aria-label={`${m.ativo ? 'Desativar' : 'Reativar'} ${m.label}`}>
              {m.ativo ? 'Desativar' : 'Reativar'}
            </Button>
          </div>
        )}
      </Card>
    </li>
  );
}

function Efeito({ icone, children }: { icone: string; children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <Icon name={icone} size={12} className="shrink-0 text-[var(--fg-3)]" />{children}
    </span>
  );
}

function ModalMotivo({ editando, cadastro, onFechar, onSalvo }: {
  editando: MotivoPerdaConfig | null; cadastro: MotivoPerdaConfig[]; onFechar: () => void; onSalvo: (msg: string) => void;
}) {
  const [r, setR] = useState<RascunhoMotivo>(() => rascunhoMotivo(editando));
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const fabrica = !!editando?.sistema;
  const mudar = (p: Partial<RascunhoMotivo>) => { setR((x) => ({ ...x, ...p })); setErro(null); };
  const chave = editando?.key ?? previaChave(r.label);

  async function salvar() {
    const v = validarMotivo(r, cadastro, editando);
    if (!v.ok) { setErro(v.erro); return; }
    setSalvando(true);
    const res = await repo.salvarMotivoPerda(v.motivo);
    setSalvando(false);
    if (res.ok) onSalvo(res.msg ?? (editando ? 'Motivo atualizado.' : 'Motivo criado.'));
    else setErro(res.msg ?? 'Não foi possível salvar.');
  }

  return (
    <Modal
      onClose={onFechar}
      title={editando ? 'Editar motivo' : 'Novo motivo de perda'}
      footer={(
        <>
          <Button size="sm" variant="ghost" onClick={onFechar} disabled={salvando}>Cancelar</Button>
          <Button size="sm" onClick={() => { void salvar(); }} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
        </>
      )}
    >
      <div className="space-y-4">
        {fabrica && (
          <p className="flex items-start gap-1.5 text-xs text-[var(--fg-3)]">
            <Icon name="lock" size={13} className="mt-0.5 shrink-0" /> Motivo do playbook: nome e efeitos são fixos. Aqui muda só a nota.
          </p>
        )}
        <Campo rotulo="Nome" dica={chave ? <>Chave: <code className="text-[var(--fg-2)]">{chave}</code></> : 'A chave sai do nome.'}>
          <Input
            value={r.label}
            onChange={(e) => mudar({ label: e.target.value })}
            disabled={fabrica}
            maxLength={LIMITE_NOME_MOTIVO}
            placeholder="ex.: Preço acima do orçamento"
            autoFocus={!fabrica}
          />
        </Campo>
        <Campo rotulo="Nota" dica="Aparece para o vendedor na hora de escolher o motivo.">
          <Textarea value={r.nota} onChange={(e) => mudar({ nota: e.target.value })} maxLength={200} rows={2} />
        </Campo>
        <fieldset className="space-y-2" disabled={fabrica}>
          <legend className="mb-1 text-xs font-medium text-[var(--fg-2)]">O que acontece com quem sai por este motivo</legend>
          <Checkbox checked={r.reativa} disabled={fabrica} onChange={(v) => mudar({ reativa: v })} label="Volta para a fila de reativação na próxima oferta" />
          <Checkbox checked={r.bloqueia} disabled={fabrica} onChange={(v) => mudar({ bloqueia: v })} label="Vai para a lista de bloqueio (não recebe mais contato)" />
          <Checkbox checked={r.alertaGestor} disabled={fabrica} onChange={(v) => mudar({ alertaGestor: v })} label="Avisa o gestor no mesmo dia (falha de processo)" />
        </fieldset>
        {erro && <Aviso tom="danger" alerta>{erro}</Aviso>}
      </div>
    </Modal>
  );
}
