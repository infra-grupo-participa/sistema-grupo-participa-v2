'use client';

import { useState } from 'react';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { Button, Card, Checkbox } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { urlDeRetorno, type PedidoAutorizacao } from '../../domain/mcp-oauth';

// Tela de consentimento do OAuth do MCP. "Permitir" chama crm_mcp_oauth_autorizar (JWT da pessoa, guarda no banco)
// e volta ao Claude com o código de uso único; "Recusar" volta com access_denied. Nada é salvo antes do clique.

function Moldura({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative min-h-dvh grid place-items-center overflow-hidden bg-[var(--surface-0)] p-4">
      <Card className="relative w-full max-w-md p-7 shadow-[var(--shadow-lg)] gp-rise">{children}</Card>
    </div>
  );
}

export function ErroAutorizacao({ msg }: { msg: string }) {
  return (
    <Moldura>
      <div className="flex flex-col items-center text-center">
        <span className="grid h-12 w-12 place-items-center rounded-[var(--r-lg)] bg-[var(--red-subtle)] text-[var(--red)]">
          <Icon name="alert" size={22} />
        </span>
        <h1 className="mt-4 text-lg font-bold text-[var(--fg)]">Não deu para conectar o Claude</h1>
        <p className="mt-2 text-sm text-[var(--fg-2)]">{msg}</p>
        <p className="mt-4 text-xs text-[var(--fg-3)]">Feche esta aba e tente de novo pelo Claude. Se continuar, fale com o gestor do Comercial.</p>
      </div>
    </Moldura>
  );
}

export function AutorizarClaudeClient({ cliente, email, pedido, emissor }: {
  cliente: string; email: string; pedido: PedidoAutorizacao; emissor: string;
}) {
  const [operar, setOperar] = useState(pedido.escopos.includes('operar'));
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const local = !pedido.redirectUri.startsWith('https://');

  async function permitir() {
    setEnviando(true);
    setErro(null);
    const { data, error } = await createBrowserSupabase().rpc('crm_mcp_oauth_autorizar', {
      p_cliente: pedido.clienteId,
      p_redirect: pedido.redirectUri,
      p_challenge: pedido.challenge,
      p_escopos: operar ? ['ler', 'operar'] : ['ler'],
    });
    const r = (data ?? {}) as { ok?: boolean; msg?: string; codigo?: string };
    if (error || r.ok !== true || !r.codigo) {
      setEnviando(false);
      setErro(r.msg ?? 'Não foi possível autorizar agora. Tente de novo.');
      return;
    }
    window.location.assign(urlDeRetorno(pedido.redirectUri, { code: r.codigo, state: pedido.state, iss: emissor }));
  }

  function recusar() {
    window.location.assign(urlDeRetorno(pedido.redirectUri, { error: 'access_denied', state: pedido.state, iss: emissor }));
  }

  return (
    <Moldura>
      <div className="flex flex-col items-center text-center">
        <span
          className="grid h-12 w-12 place-items-center rounded-[var(--r-lg)] text-[var(--accent)]"
          style={{ background: 'color-mix(in srgb, var(--accent) 14%, transparent)' }}
        >
          <Icon name="link" size={22} />
        </span>
        <h1 className="mt-4 text-lg font-bold text-[var(--fg)]">Conectar o Claude ao CRM Comercial</h1>
        <p className="mt-1 text-sm text-[var(--fg-3)]">
          <strong className="text-[var(--fg-2)]">{cliente}</strong> quer acessar o CRM como <strong className="text-[var(--fg-2)]">{email}</strong>.
        </p>
      </div>

      <div className="mt-6 space-y-3 text-sm text-[var(--fg-2)]">
        <p className="font-medium text-[var(--fg)]">O Claude vai poder:</p>
        <ul className="space-y-1.5">
          <li className="flex gap-2"><Icon name="check" size={16} className="mt-0.5 shrink-0 text-[var(--green)]" />Ver os seus negócios, contatos, atividades e conversas — só o que você já vê no CRM.</li>
          <li className="flex gap-2"><Icon name="x" size={16} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />Nunca envia WhatsApp, não marca ganho/perdido, não troca dono, não vê CPF.</li>
        </ul>
        <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
          <Checkbox
            checked={operar}
            onChange={setOperar}
            label="Também registrar por mim: atividades (criar, concluir, reabrir), notas, mover etapa, criar e editar contato e tags"
          />
          <p className="mt-1.5 pl-6 text-xs text-[var(--fg-3)]">Tudo fica no Registro do CRM como feito “via Claude”, no seu nome.</p>
        </div>
        {local && <p className="text-xs text-[var(--fg-3)]">Pedido vindo de um programa no seu computador (Claude Code/Desktop).</p>}
        <p className="text-xs text-[var(--fg-3)]">
          Dados de clientes são pessoais (LGPD): use só para o atendimento. Você pode desligar a conexão a qualquer momento em
          Comercial → Configurações → Conectar ao Claude.
        </p>
      </div>

      {erro && <p role="alert" className="mt-4 flex items-center gap-1.5 text-sm text-[var(--red)]"><Icon name="alert" size={14} />{erro}</p>}

      <div className="mt-6 flex gap-3">
        <Button variant="ghost" className="flex-1" onClick={recusar} disabled={enviando}>Recusar</Button>
        <Button className="flex-1" onClick={permitir} disabled={enviando}>{enviando ? 'Conectando…' : 'Permitir'}</Button>
      </div>
    </Moldura>
  );
}
