import type { SupabaseClient } from '@supabase/supabase-js';
import type { ProfileRepository } from '@/shared/application/auth/ports';
import type { PerfilData } from '@/shared/domain/auth';

const PERFIL_COLUMNS =
  'id, nome, email, cargo, status, nivel_hierarquia, eh_dev, pode_ver_cpf_completo, time, avatar_url, areas, setores, funcoes';

/** Adapter do port ProfileRepository sobre a tabela `perfis`. */
export class SupabaseProfileRepository implements ProfileRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  async findById(id: string): Promise<PerfilData | null> {
    const { data } = await this.supabase
      .from('perfis')
      .select(PERFIL_COLUMNS)
      .eq('id', id)
      .single();
    return (data as PerfilData) ?? null;
  }
}
