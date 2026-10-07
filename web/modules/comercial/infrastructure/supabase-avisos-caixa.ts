'use client';

// Aviso do banco de que a caixa do WhatsApp mudou (migration 20261007153421): Supabase Realtime, Broadcast no canal
// PRIVADO "crm:caixa". Só quem é do Comercial entra (policy crm_caixa_ouvir em realtime.messages). O payload é só
// {t: 'mensagem' | 'conversa'}, sem dado pessoal: quem ouve recarrega pelas RPCs de sempre, que aplicam as permissões.
import type { RealtimeChannel } from '@supabase/supabase-js';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';

export const TOPICO_CAIXA = 'crm:caixa';

/**
 * Assina os avisos. `aoAvisar` a cada mudança; `aoEstado(true)` quando o canal entra (inclusive ao reconectar),
 * `false` quando cai (o supabase-js tenta de novo sozinho). Devolve o cancelamento.
 */
export function assinarAvisosCaixa(aoAvisar: () => void, aoEstado: (conectado: boolean) => void): () => void {
  const sb = createBrowserSupabase();
  const canal: RealtimeChannel = sb
    .channel(TOPICO_CAIXA, { config: { private: true } })
    .on('broadcast', { event: 'mudou' }, () => aoAvisar())
    .subscribe((status) => aoEstado(status === 'SUBSCRIBED'));
  return () => {
    aoEstado(false);
    void sb.removeChannel(canal);
  };
}
