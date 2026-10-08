'use client';

// Nova conversa: número → pessoa → começar, numa tela só. Nada é enviado aqui: "Começar" abre a conversa (a que já
// existe com a pessoa nesse número, ou uma vazia pronta para digitar). A 1ª mensagem cria a crm.conversa com o número
// escolhido (crm_enviar_mensagem p_canal), como na Onda 1. Regras visíveis antes de enviar: domain/nova-conversa.ts.
import { useEffect, useMemo, useState } from 'react';
import { Button, Modal, SearchInput } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtTelefone } from '../../domain/regras';
import { rotuloCanal, type CanalWhatsapp, type PainelCanais } from '../../domain/canais-whatsapp';
import {
  avisoLimiteQr, bloqueioPessoaNovaConversa, canaisParaNovaConversa, canalInicialNovaConversa, janelaDoCanal, modoEnvio, rotuloProvedor,
} from '../../domain/nova-conversa';
import type { Contato, Conversa, Negocio, SessaoComercial } from '../../domain/types';
import { Aviso, Campo, NotaRodape, Pessoa, Sinal } from '../comum';
import { ModalNovoContato } from '../contatos/ModalNovoContato';
import { repo, useDados } from '../repositorio';

const MAX_RESULTADOS = 8;

export function ModalNovaConversa({ canais, painel, sessao, conversas, nomeDe, agora, onClose, onComecar }: {
  canais: CanalWhatsapp[];
  painel: PainelCanais | null;
  sessao: SessaoComercial;
  conversas: Conversa[];
  nomeDe: (id: string | null) => string;
  agora: Date;
  onClose: () => void;
  onComecar: (contatoId: string, canalId: string) => void;
}) {
  const disponiveis = useMemo(() => canaisParaNovaConversa(canais, painel, sessao), [canais, painel, sessao]);
  const [canalId, setCanalId] = useState<string | null>(() => canalInicialNovaConversa(disponiveis));
  const canal = disponiveis.find((c) => c.id === canalId) ?? null;

  const [busca, setBusca] = useState('');
  const [termo, setTermo] = useState('');
  useEffect(() => {
    const t = setTimeout(() => setTermo(busca.trim()), 400);
    return () => clearTimeout(t);
  }, [busca]);
  const rBusca = useDados(async () => (termo.length < 3 ? [] as Contato[] : repo.buscarContatos(termo)), [termo]);
  const [contato, setContato] = useState<Contato | null>(null);
  const [cadastrando, setCadastrando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  // Todos os negócios da pessoa (qualquer status): dono de algum deles escreve (D6, crm.pode_escrever_pessoa).
  const rNegocios = useDados(async () => (contato ? repo.negocios({ contatoId: contato.id }) : [] as Negocio[]), [contato?.id ?? null]);
  const negociosOk = !contato || (!!rNegocios.dados && !rNegocios.carregando);
  const bloqueio = contato && negociosOk ? bloqueioPessoaNovaConversa(contato, rNegocios.dados ?? [], sessao, nomeDe) : null;

  const conversa = contato ? conversas.find((c) => c.contatoId === contato.id) ?? null : null;
  const jaNoNumero = !!conversa && !!canal && (conversa.canais ?? (conversa.canalId ? [conversa.canalId] : [])).includes(canal.id);
  const modo = canal ? modoEnvio(canal, janelaDoCanal(conversa, canal.id), agora) : null;
  const pode = !!canal && !!contato && negociosOk && !bloqueio;

  const escolherPorId = async (id: string, local: Contato | null) => {
    setCadastrando(false);
    setErro(null);
    if (local) { setContato(local); return; }
    try {
      const [c] = await repo.contatosPorIds([id]);
      if (c) setContato(c); else setErro('Contato salvo, mas fora da sua visão. Fale com o gestor.');
    } catch { setErro('Não foi possível carregar o contato.'); }
  };

  if (cadastrando) {
    const dig = busca.replace(/\D/g, '');
    const pareceTelefone = dig.length >= 8 && dig.length >= busca.replace(/\s/g, '').length - 4;
    return (
      <ModalNovoContato
        titulo="Cadastrar contato novo"
        rotuloAbrir="Usar este"
        inicial={pareceTelefone ? { telefone: busca.trim() } : busca.includes('@') ? { email: busca.trim() } : { nome: busca.trim() }}
        nomeDe={nomeDe}
        onClose={() => setCadastrando(false)}
        onAbrirContato={(id) => void escolherPorId(id, null)}
        onCriado={({ contatoId, local }) => void escolherPorId(contatoId, local)}
      />
    );
  }

  const achados = rBusca.dados ?? [];
  const lista = achados.slice(0, MAX_RESULTADOS);

  return (
    <Modal
      onClose={onClose}
      title="Nova conversa"
      footer={<>
        <Button size="sm" variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button size="sm" disabled={!pode} onClick={() => canal && contato && onComecar(contato.id, canal.id)}>
          <Icon name="message" size={14} /> {jaNoNumero ? 'Abrir conversa' : 'Começar conversa'}
        </Button>
      </>}
    >
      <div className="space-y-5">
        {/* 1. Número */}
        <Campo rotulo="1. Número">
          {disponiveis.length === 0 ? (
            <Aviso tom="warning" icone="alert">Nenhum número conectado que envie pelo CRM agora. O gestor confere em Configurações.</Aviso>
          ) : (
            <div role="radiogroup" aria-label="Número de WhatsApp" className="grid gap-2 sm:grid-cols-2">
              {disponiveis.map((c) => {
                const sel = c.id === canalId;
                return (
                  <button
                    key={c.id}
                    type="button"
                    role="radio"
                    aria-checked={sel}
                    onClick={() => setCanalId(c.id)}
                    className={`flex items-center justify-between gap-2 rounded-[var(--r-md)] border px-3 py-2 text-left text-sm transition-colors ${
                      sel ? 'border-[var(--accent-border)] bg-[var(--accent-subtle)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-2)] hover:bg-[var(--surface-3)]'
                    }`}
                  >
                    <span className="min-w-0 truncate font-medium">{rotuloCanal(c)}</span>
                    <span className="shrink-0 rounded-[var(--r-pill)] border border-[var(--border)] px-1.5 text-[10px] leading-4 text-[var(--fg-3)]">{rotuloProvedor(c)}</span>
                  </button>
                );
              })}
            </div>
          )}
        </Campo>

        {/* 2. Pessoa */}
        <div>
          <Campo rotulo="2. Pessoa" dica="Busque pelo telefone antes de cadastrar: tem dono, não é seu.">
            {contato ? (
              <div className="flex items-center justify-between gap-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2">
                <Pessoa nome={contato.nome} sub={`${contato.telefone ? fmtTelefone(contato.telefone) : 'sem telefone'} · ${contato.donoId ? nomeDe(contato.donoId) : 'sem dono'}`} size={28} />
                <Button size="sm" variant="link" onClick={() => { setContato(null); setErro(null); }}>Trocar</Button>
              </div>
            ) : (
              <SearchInput
                autoFocus={disponiveis.length <= 1}
                placeholder="Nome, telefone ou e-mail"
                value={busca}
                onChange={(e) => { setBusca(e.target.value); setErro(null); }}
                onLimpar={() => setBusca('')}
              />
            )}
          </Campo>
          {!contato && (
            <>
              <div role="listbox" aria-label="Pessoas encontradas" className="mt-2 max-h-56 overflow-y-auto rounded-[var(--r-md)] border border-[var(--border)]">
                {lista.length === 0 && (
                  <div className="px-3 py-4 text-center text-xs text-[var(--fg-3)]">
                    {busca.trim().length < 3 ? 'Digite ao menos 3 letras do nome, o telefone ou o e-mail.'
                      : rBusca.carregando || termo !== busca.trim() ? 'Buscando…' : `Ninguém com “${busca.trim()}”.`}
                  </div>
                )}
                {lista.map((c) => (
                  <button
                    key={c.id}
                    type="button"
                    role="option"
                    aria-selected={false}
                    onClick={() => { setContato(c); setErro(null); }}
                    className="w-full flex items-center justify-between gap-3 px-3 py-2 text-left border-b border-[var(--border-faint)] last:border-0 hover:bg-[var(--surface-3)]"
                  >
                    <Pessoa
                      nome={c.nome}
                      sub={c.telefone ? fmtTelefone(c.telefone) : c.email ?? 'sem telefone'}
                      size={24}
                      flags={c.ehAluno ? <Sinal icone="graduation" rotulo="Já é aluno" /> : undefined}
                    />
                    <span className={`shrink-0 text-xs ${c.optOut ? 'font-medium text-[var(--red)]' : 'text-[var(--fg-3)]'}`}>
                      {c.optOut ? 'não quer contato' : c.donoId ? `dono: ${nomeDe(c.donoId)}` : 'sem dono'}
                    </span>
                  </button>
                ))}
              </div>
              <div className="mt-1 flex flex-wrap items-center justify-between gap-2">
                {achados.length > MAX_RESULTADOS ? <NotaRodape>Mostrando {MAX_RESULTADOS} de {achados.length}. Refine pelo telefone.</NotaRodape> : <span />}
                <Button size="sm" variant="link" onClick={() => setCadastrando(true)}><Icon name="plus" size={13} /> Cadastrar contato novo</Button>
              </div>
            </>
          )}
        </div>

        {/* 3. Começar: o que vai acontecer, dito antes */}
        {contato && canal && (
          !negociosOk ? (
            <NotaRodape>Conferindo quem pode falar com esta pessoa…</NotaRodape>
          ) : bloqueio ? (
            <Aviso tom="danger" icone="lock">{bloqueio}</Aviso>
          ) : (
            <div className="space-y-2">
              {jaNoNumero && <NotaRodape>Já existe conversa com {contato.nome} neste número: ela abre com o histórico.</NotaRodape>}
              {modo === 'template' ? (
                <Aviso tom="info" icone="file">Número oficial fora da janela de 24 h: a primeira mensagem sai por template aprovado (você escolhe na conversa).</Aviso>
              ) : canal.provedor === 'evolution' ? (
                <NotaRodape>{avisoLimiteQr(painel)}</NotaRodape>
              ) : (
                <NotaRodape>Janela de 24 h aberta neste número: texto livre.</NotaRodape>
              )}
            </div>
          )
        )}
        {erro && <Aviso tom="danger" alerta>{erro}</Aviso>}
      </div>
    </Modal>
  );
}
