'use client';

// Aviso do banco de que a caixa do WhatsApp mudou (migration 20261007153421): Supabase Realtime, Broadcast no canal
// PRIVADO "crm:caixa". Só quem é do Comercial entra (policy crm_caixa_ouvir em realtime.messages). O payload é só
// {t: 'mensagem' | 'conversa'}, sem dado pessoal: quem ouve recarrega pelas RPCs de sempre, que aplicam as permissões.
import type { RealtimeChannel } from '@supabase/supabase-js';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';

export const TOPICO_CAIXA = 'crm:caixa';

// Remoção do canal anterior ainda em curso: criar o mesmo tópico antes dela terminar dá
// "tried to subscribe multiple times". A assinatura nova espera esta promessa.
let removendo: Promise<unknown> | null = null;

/**
 * Assina os avisos. `aoAvisar` a cada mudança; `aoEstado(true)` quando o canal entra (inclusive ao reconectar),
 * `false` quando cai (o supabase-js tenta de novo sozinho). Devolve o cancelamento.
 */
export function assinarAvisosCaixa(aoAvisar: () => void, aoEstado: (conectado: boolean) => void): () => void {
  const sb = createBrowserSupabase();
  let canal: RealtimeChannel | null = null;
  let cancelado = false;
  const abrir = () => {
    if (cancelado) return;
    canal = sb
      .channel(TOPICO_CAIXA, { config: { private: true } })
      .on('broadcast', { event: 'mudou' }, () => aoAvisar())
      .subscribe((status) => aoEstado(status === 'SUBSCRIBED'));
  };
  if (removendo) void removendo.finally(abrir); else abrir();
  return () => {
    cancelado = true;
    aoEstado(false);
    if (!canal) return;
    const p = sb.removeChannel(canal).catch(() => undefined);
    removendo = p;
    void p.finally(() => { if (removendo === p) removendo = null; });
  };
}
