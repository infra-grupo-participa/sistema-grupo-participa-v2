'use client';

// Aba #mcp: token pessoal para conectar o Claude (Code ou Desktop) ao CRM (F7). Cada pessoa gera os próprios tokens;
// o gestor vê e revoga os do time. O token completo aparece UMA vez (o banco guarda só o sha-256).
import { useState } from 'react';
import {
  Badge, Button, ConfirmDialog, CopyField, FilterSelect, Input, SectionCard,
} from '@/shared/ui/components';
import { fmtData, fmtDataHora, fmtRelativo } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import type { SessaoComercial, TokenMcp } from '../../domain/types';
import { Aviso, Campo, Carregando, EsqueletoLista, NotaRodape, Segmentado } from '../comum';
import { repo, useAgora, useDados } from '../repositorio';
import {
  MAX_TOKENS_ATIVOS, URL_MCP, VALIDADES_TOKEN, ativosDe, comandoClaudeCode, configClaudeDesktop, ehRespostaMcpDesligado,
  escoposDoNovoToken, estadoMcp, ordenarTokens, rotuloEscopos, situacaoToken, validarNovoToken, type SituacaoToken,
} from './regras-integracoes';

const TOM_SITUACAO: Record<SituacaoToken, 'success' | 'neutral' | 'danger'> = { ativo: 'success', expirado: 'neutral', revogado: 'danger' };
const ROTULO_SITUACAO: Record<SituacaoToken, string> = { ativo: 'Ativo', expirado: 'Expirado', revogado: 'Revogado' };

export function AbaMcp({ sessao, gestor, flash }: { sessao: SessaoComercial; gestor: boolean; flash: (m: string) => void }) {
  const agora = useAgora();
  const rTokens = useDados(() => repo.tokensMcp());
  const rConfig = useDados(() => repo.config());
  const [respostaDesligado, setRespostaDesligado] = useState(false);
  const [gerado, setGerado] = useState<{ token: string; nome: string } | null>(null);
  const estado = estadoMcp(rConfig.dados?.mcpLigado, respostaDesligado);

  return (
    <div className="space-y-4">
      {estado === 'desligado' && (
        <Aviso tom="warning" icone="lock" titulo="O MCP do Comercial está desligado">
          Nenhum token conecta agora e não dá para gerar token novo. Revogar continua funcionando. Quem liga é o
          responsável pelo sistema, depois do ok do gestor sobre os dados que vão para o Claude.
        </Aviso>
      )}

      <div className="grid gap-4 xl:grid-cols-[3fr_2fr]">
        <div className="min-w-0 space-y-4">
          {gerado ? (
            <TokenGerado token={gerado.token} nome={gerado.nome} onFechar={() => setGerado(null)} />
          ) : (
            <NovoToken
              ativosMeus={ativosDe(rTokens.dados ?? [], sessao.vendedorId, agora)}
              bloqueado={estado === 'desligado'}
              onCriado={(token, nome) => { setGerado({ token, nome }); void rTokens.recarregar(); }}
              onDesligado={() => setRespostaDesligado(true)}
              flash={flash}
            />
          )}

          <SectionCard
            title={gestor ? 'Tokens do time' : 'Seus tokens'}
            subtitle={gestor ? 'Você vê e revoga os tokens de todos do Comercial.' : `Até ${MAX_TOKENS_ATIVOS} ativos por pessoa. Revogue o que não usa mais.`}
          >
            <Carregando dados={rTokens.dados} erro={rTokens.erro} onTentar={() => void rTokens.recarregar()} esqueleto={<EsqueletoLista linhas={2} avatar={false} />}>
              {(lista) => lista.length === 0 ? (
                <p className="text-xs text-[var(--fg-3)]">Nenhum token ainda.</p>
              ) : (
                <ListaTokens lista={ordenarTokens(lista, agora)} agora={agora} gestor={gestor} meuId={sessao.vendedorId}
                  onRevogado={(msg) => { flash(msg); void rTokens.recarregar(); }} />
              )}
            </Carregando>
          </SectionCard>
        </div>

        <ComoConectar token={gerado?.token ?? null} />
      </div>
    </div>
  );
}

function NovoToken({ ativosMeus, bloqueado, onCriado, onDesligado, flash }: {
  ativosMeus: number; bloqueado: boolean; onCriado: (token: string, nome: string) => void; onDesligado: () => void; flash: (m: string) => void;
}) {
  const [nome, setNome] = useState('');
  const [operar, setOperar] = useState(false);
  const [dias, setDias] = useState(90);
  const [enviando, setEnviando] = useState(false);
  const problema = validarNovoToken({ nome, operar, dias }, ativosMeus);

  async function gerar() {
    if (problema || bloqueado) return;
    setEnviando(true);
    const r = await repo.criarTokenMcp(nome, escoposDoNovoToken(operar), dias);
    setEnviando(false);
    if (r.ok && r.token) { onCriado(r.token, nome.trim()); setNome(''); setOperar(false); return; }
    if (ehRespostaMcpDesligado(r.msg)) onDesligado();
    flash(r.msg ?? 'Não foi possível gerar o token.');
  }

  return (
    <SectionCard title="Novo token" subtitle="Um token por lugar onde você usa o Claude (ex.: notebook, Claude Desktop).">
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); void gerar(); }}>
        <div className="grid gap-3 sm:grid-cols-[2fr_1fr]">
          <Campo rotulo="Nome" dica="Só para você reconhecer depois.">
            <Input value={nome} maxLength={60} placeholder="Claude Code notebook" onChange={(e) => setNome(e.target.value)} />
          </Campo>
          <Campo rotulo="Validade">
            <FilterSelect value={String(dias)} onChange={(e) => setDias(Number(e.target.value))}>
              {VALIDADES_TOKEN.map((d) => <option key={d} value={d}>{d} dias</option>)}
            </FilterSelect>
          </Campo>
        </div>
        <div>
          <span className="mb-1 block text-xs font-medium text-[var(--fg-2)]">O que o Claude pode fazer</span>
          <Segmentado
            rotulo="Escopo do token"
            valor={operar ? 'operar' : 'ler'}
            onChange={(v) => setOperar(v === 'operar')}
            opcoes={[{ valor: 'ler', rotulo: 'Só leitura' }, { valor: 'operar', rotulo: 'Ler e operar' }]}
          />
          <p className="mt-1.5 text-xs text-[var(--fg-3)] leading-relaxed">
            {operar
              ? 'Consulta e também agenda atividade, registra nota e move etapa, com as mesmas regras da tela. Não marca ganho nem perdido, não troca dono, não dispara.'
              : 'Consulta funis, negócios, pessoas, atividades do dia e desempenho. Não grava nada.'}
          </p>
        </div>
        <div className="flex flex-wrap items-center justify-end gap-3">
          {problema && (nome.trim() || ativosMeus >= MAX_TOKENS_ATIVOS) && <span className="text-xs text-[var(--red)]">{problema}</span>}
          <Button type="submit" size="sm" disabled={!!problema || bloqueado || enviando} title={bloqueado ? 'MCP desligado' : problema ?? undefined}>
            <Icon name="plus" size={14} /> {enviando ? 'Gerando…' : 'Gerar token'}
          </Button>
        </div>
      </form>
    </SectionCard>
  );
}

function TokenGerado({ token, nome, onFechar }: { token: string; nome: string; onFechar: () => void }) {
  return (
    <SectionCard title={`Token "${nome}" criado`} subtitle="Copie agora: ele não aparece de novo. Se perder, revogue e gere outro.">
      <div className="space-y-3">
        <CopyField label="Seu token" value={token} />
        <Aviso tom="warning" icone="lock">
          Trate como senha: não mande no Slack nem cole em documento. Quem tem o token age no CRM como você.
        </Aviso>
        <div className="flex justify-end">
          <Button size="sm" variant="subtle" onClick={onFechar}><Icon name="check" size={14} /> Já copiei</Button>
        </div>
      </div>
    </SectionCard>
  );
}

function ListaTokens({ lista, agora, gestor, meuId, onRevogado }: {
  lista: TokenMcp[]; agora: Date; gestor: boolean; meuId: string; onRevogado: (msg: string) => void;
}) {
  const [revogar, setRevogar] = useState<TokenMcp | null>(null);
  async function confirmar() {
    if (!revogar) return;
    const t = revogar;
    setRevogar(null);
    const r = await repo.revogarTokenMcp(t.id);
    onRevogado(r.ok ? r.msg ?? `Token "${t.nome}" revogado.` : r.msg ?? 'Não foi possível revogar.');
  }
  return (
    <>
      {/* Uma linha por token que quebra em tela estreita (sem tabela com rolagem). */}
      <ul className="divide-y divide-[var(--border-faint)] rounded-[var(--r-md)] border border-[var(--border)]">
        {lista.map((t) => {
          const sit = situacaoToken(t, agora);
          return (
            <li key={t.id} className="flex flex-wrap items-center gap-x-3 gap-y-1.5 px-3 py-2">
              <div className="min-w-0 flex-1 basis-[220px]">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium text-[var(--fg)] truncate">{t.nome}</span>
                  <Badge tone={TOM_SITUACAO[sit]}>{ROTULO_SITUACAO[sit]}</Badge>
                  <span className="text-xs text-[var(--fg-3)]">{rotuloEscopos(t.escopos)}</span>
                </div>
                <div className="text-xs text-[var(--fg-3)]">
                  <span className="font-mono">{t.prefixo}…</span>
                  {gestor && t.perfilId !== meuId && <> · de {t.perfilNome || 'outra pessoa'}</>}
                  {' · '}{sit === 'revogado' ? `revogado ${fmtDataHora(t.revogadoEm)}` : `${sit === 'ativo' ? 'vale até' : 'venceu em'} ${fmtData(t.expiraEm)}`}
                  {' · '}<span title={t.ultimoUsoEm ? fmtDataHora(t.ultimoUsoEm) : undefined}>{t.ultimoUsoEm ? `usado ${fmtRelativo(t.ultimoUsoEm).label}` : 'nunca usado'}</span>
                </div>
              </div>
              {sit === 'ativo' && (
                <Button size="sm" variant="danger" onClick={() => setRevogar(t)}><Icon name="x" size={14} /> Revogar</Button>
              )}
            </li>
          );
        })}
      </ul>
      {revogar && (
        <ConfirmDialog
          danger
          title="Revogar token"
          confirmLabel="Revogar"
          message={<>O Claude conectado com <b>{revogar.nome}</b> ({revogar.prefixo}…) perde o acesso na hora. Não dá para desfazer.</>}
          onConfirm={() => void confirmar()}
          onCancel={() => setRevogar(null)}
        />
      )}
    </>
  );
}

function Bloco({ titulo, texto }: { titulo: string; texto: string }) {
  const [copiado, setCopiado] = useState(false);
  const copiar = async () => {
    try { await navigator.clipboard.writeText(texto); setCopiado(true); setTimeout(() => setCopiado(false), 1500); } catch { /* texto continua selecionável */ }
  };
  return (
    <div>
      <div className="mb-1 flex items-center justify-between gap-2">
        <span className="text-xs font-medium text-[var(--fg-2)]">{titulo}</span>
        <Button size="sm" variant="ghost" onClick={copiar} aria-label={`Copiar: ${titulo}`}>
          <Icon name={copiado ? 'check' : 'copy'} size={13} /> {copiado ? 'Copiado' : 'Copiar'}
        </Button>
      </div>
      {/* Quebra a linha em vez de rolar para o lado. */}
      <pre className="whitespace-pre-wrap break-all rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] px-3 py-2 font-mono text-[11px] leading-relaxed text-[var(--fg)]">{texto}</pre>
    </div>
  );
}

function ComoConectar({ token }: { token: string | null }) {
  return (
    <SectionCard title="Como conectar" subtitle={token ? 'Os comandos abaixo já estão com o seu token novo.' : 'Troque gpc_SEU_TOKEN pelo token gerado.'}>
      <div className="space-y-4 text-xs text-[var(--fg-2)] leading-relaxed">
        <p>
          O Claude passa a consultar o CRM como você: vê o que você vê na tela, com as mesmas regras. Endereço do servidor:{' '}
          <code className="break-all text-[var(--fg)]">{URL_MCP}</code>
        </p>
        <Bloco titulo="Claude Code (terminal)" texto={comandoClaudeCode(token)} />
        <div className="space-y-2">
          <p>
            <b className="text-[var(--fg)]">Claude Desktop:</b> Configurações › Desenvolvedor › Editar config. Cole o trecho no
            arquivo <code>claude_desktop_config.json</code> e reinicie o app. Precisa do Node instalado.
          </p>
          <Bloco titulo="claude_desktop_config.json" texto={configClaudeDesktop(token)} />
        </div>
        <p>
          <b className="text-[var(--fg)]">claude.ai no navegador e app do celular:</b> ainda não conectam (pedem outro tipo de
          login). Use o Claude Code ou o Claude Desktop.
        </p>
        <p>Para testar, peça ao Claude: &quot;liste os funis do comercial&quot;.</p>
        <NotaRodape>
          Toda gravação feita pelo Claude entra no Registro do CRM com o seu nome. Limite de 60 pedidos por minuto por token.
          CPF nunca sai; e-mail e telefone só aparecem completos para o dono do contato ou o gestor.
        </NotaRodape>
      </div>
    </SectionCard>
  );
}
