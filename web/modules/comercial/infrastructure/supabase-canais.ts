// Portas do banco para os números conectados por QR (servidor). `usuario` = client com o JWT de quem clicou (o portão
// confere gestor do CRM); `servico` = service role, só chamado depois do portão (guarda QR/estado, lê a chave do webhook).
import { createServerSupabase } from '@/shared/infrastructure/supabase/server-client';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import type { PortasCanais, ResultadoRpc } from '../application/canais-whatsapp';

function resultado(data: unknown, error: { message?: string } | null): ResultadoRpc {
  if (error) return { ok: false, msg: 'Não foi possível falar com o banco.' };
  return data && typeof data === 'object' && !Array.isArray(data) && typeof (data as ResultadoRpc).ok === 'boolean'
    ? (data as ResultadoRpc)
    : { ok: false, msg: 'Resposta inesperada do banco.' };
}

export async function portasCanais(): Promise<PortasCanais> {
  const usuario = await createServerSupabase();
  return {
    async criarCanal(nome) {
      const { data, error } = await usuario.rpc('crm_canal_criar', { p_nome: nome });
      return resultado(data, error);
    },
    async portao(canalId, acao) {
      const { data, error } = await usuario.rpc('crm_canal_portao', { p_canal: canalId, p_acao: acao });
      return resultado(data, error);
    },
    async servico(acao, canalId, dados = {}) {
      const { data, error } = await createAdminSupabase().rpc('crm_evolution_servico', { p_acao: acao, p_canal: canalId, p_dados: dados });
      return resultado(data, error);
    },
  };
}
