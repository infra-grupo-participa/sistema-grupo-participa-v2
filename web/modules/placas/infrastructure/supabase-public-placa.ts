import type { SupabaseClient } from '@supabase/supabase-js';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';

// Gateway do fluxo PÚBLICO de placa — porta de placa-public.php.
// Usa service_role (token UUID é a fronteira de segurança), como no PHP legado.

const PUBLIC_FIELDS =
  'id,token,status,step_index,auditoria_step,nome,email,telefone,turma,profissao,telefone_profissional,youtube_url,site_profissional,instagram_url,facebook_url,interesse,espaco_instrucao,nivel,faturamento_declarado,proof_url,declaracao_url,cep,logradouro,numero,complemento,bairro,cidade,estado_uf,pais,documento_nf,entrevista_data,entrevista_hora,entrevista_link,meet_link,codigo_rastreio,motivo_retorno';

type Row = Record<string, unknown>;

/** Mascara URLs de documento como 'uploaded' (resposta pública não expõe a URL real). */
export function maskDocsForPublic(row: Row): Row {
  const out = { ...row };
  if (out.proof_url) out.proof_url = 'uploaded';
  if (out.declaracao_url) out.declaracao_url = 'uploaded';
  return out;
}

export class SupabasePublicPlaca {
  private db: SupabaseClient;
  constructor(db?: SupabaseClient) {
    this.db = db ?? createAdminSupabase();
  }

  /** Carrega a linha CRUA (URLs reais) — usado para validação interna. */
  async loadByToken(token: string): Promise<Row | null> {
    const { data } = await this.db
      .from('thb_placas_solicitacoes')
      .select(PUBLIC_FIELDS)
      .eq('token', token)
      .limit(1)
      .maybeSingle();
    return (data as Row) ?? null;
  }

  async duplicateExists(field: 'email' | 'documento_nf', value: string, token: string, includeRascunho: boolean): Promise<boolean> {
    let q = this.db.from('thb_placas_solicitacoes').select('token,status').eq(field, value);
    if (!includeRascunho) q = q.neq('status', 'rascunho');
    const { data } = await q;
    return (data ?? []).some((r) => {
      const t = String((r as Row).token ?? '').toLowerCase().trim();
      return t !== '' && t !== token;
    });
  }

  async recoverSession(email: string, documento: string): Promise<Row | null> {
    const { data } = await this.db
      .from('thb_placas_solicitacoes')
      .select(PUBLIC_FIELDS)
      .eq('email', email)
      .eq('documento_nf', documento)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    return (data as Row) ?? null;
  }

  async create(payload: Row): Promise<Row | null> {
    const { data } = await this.db
      .from('thb_placas_solicitacoes')
      .insert(payload)
      .select('token,status,step_index')
      .single();
    return (data as Row) ?? null;
  }

  async updateByToken(token: string, payload: Row): Promise<void> {
    await this.db.from('thb_placas_solicitacoes').update(payload).eq('token', token);
  }

  /** Linha mínima para validar um upload (status + step). */
  async loadForUpload(token: string): Promise<{ id: string; status: string; step_index: number } | null> {
    const { data } = await this.db
      .from('thb_placas_solicitacoes')
      .select('id,status,step_index')
      .eq('token', token)
      .limit(1)
      .maybeSingle();
    return (data as { id: string; status: string; step_index: number }) ?? null;
  }

  /** Sobe um documento ao bucket `documentos` e retorna a URL pública. */
  async uploadDocumento(path: string, buffer: Buffer, mime: string): Promise<string | null> {
    const { error } = await this.db.storage
      .from('documentos')
      .upload(path, buffer, { contentType: mime, upsert: false });
    if (error) return null;
    return this.db.storage.from('documentos').getPublicUrl(path).data.publicUrl;
  }

  /** Slots ativos a partir de hoje (fuso America/Sao_Paulo). */
  async loadActiveSlots(todayIso: string): Promise<Row[]> {
    const { data } = await this.db
      .from('thb_horarios_disponiveis')
      .select('id,slot_data,hora,ativo')
      .gte('slot_data', todayIso)
      .eq('ativo', true)
      .order('slot_data', { ascending: true })
      .order('hora', { ascending: true });
    return (data as Row[]) ?? [];
  }

  /** Entrevistas marcadas (para desabilitar slots ocupados no calendário). */
  async loadBookedSlots(limitDateIso: string | null): Promise<Array<{ entrevista_data: string; entrevista_hora: string }>> {
    let q = this.db
      .from('thb_placas_solicitacoes')
      .select('token,status,auditoria_step,entrevista_data,entrevista_hora')
      .not('entrevista_data', 'is', null);
    if (limitDateIso) q = q.lte('entrevista_data', limitDateIso);
    const { data } = await q;
    return (data ?? [])
      .filter((r) => {
        const status = String((r as Row).status ?? '');
        if (['concluido', 'rejeitado'].includes(status)) return false;
        const auditStep = Math.max(Number((r as Row).step_index ?? -1), Number((r as Row).auditoria_step ?? -1));
        return auditStep < 3;
      })
      .map((r) => ({
        entrevista_data: String((r as Row).entrevista_data ?? ''),
        entrevista_hora: String((r as Row).entrevista_hora ?? '').slice(0, 5),
      }))
      .filter((s) => s.entrevista_data && s.entrevista_hora);
  }

  /**
   * Promove dados da solicitação para thb_alunos (apenas no submit final).
   * Seta placa_solicitacao_id sempre; campos de contato só se atualizado_por IS NULL.
   * Não-crítico: erros são engolidos.
   */
  async promoteToAluno(token: string, payload: Row): Promise<void> {
    try {
      const email = String(payload.email ?? '').trim();
      if (!email) return;

      const { data: sol } = await this.db
        .from('thb_placas_solicitacoes')
        .select('id')
        .eq('token', token)
        .limit(1)
        .maybeSingle();
      const solicitacaoId = (sol as Row)?.id;
      if (!solicitacaoId) return;

      const { data: aluno } = await this.db
        .from('thb_alunos')
        .select(
          'id,atualizado_por,placa_solicitacao_id,telefone,documento,cep,cidade,estado,bairro,pais,endereco_logradouro,endereco_numero,endereco_complemento,profissao,telefone_profissional,instagram_url,youtube_url,site_profissional,link_facebook',
        )
        .ilike('email', email)
        .limit(1)
        .maybeSingle();
      const a = aluno as Row | null;
      if (!a?.id) return;

      const updates: Row = { placa_solicitacao_id: solicitacaoId };
      const audit: Row[] = [];
      if (a.placa_solicitacao_id !== solicitacaoId) {
        audit.push({ aluno_id: a.id, campo: 'placa_solicitacao_id', valor_anterior: null, valor_novo: String(solicitacaoId), origem: 'form_publico_placa' });
      }

      if (!a.atualizado_por) {
        const fieldMap: Record<string, string> = {
          telefone: 'telefone',
          documento: 'documento_nf',
          cep: 'cep',
          cidade: 'cidade',
          estado: 'estado_uf',
          bairro: 'bairro',
          pais: 'pais',
          endereco_logradouro: 'logradouro',
          endereco_numero: 'numero',
          endereco_complemento: 'complemento',
          profissao: 'profissao',
          telefone_profissional: 'telefone_profissional',
          instagram_url: 'instagram_url',
          youtube_url: 'youtube_url',
          site_profissional: 'site_profissional',
          link_facebook: 'facebook_url',
        };
        for (const [col, key] of Object.entries(fieldMap)) {
          if (!Object.prototype.hasOwnProperty.call(payload, key)) continue;
          const novo = payload[key];
          if (novo === null || novo === '') continue;
          const atual = a[col] ?? null;
          if (atual !== null && String(atual) === String(novo)) continue;
          updates[col] = novo;
          audit.push({ aluno_id: a.id, campo: col, valor_anterior: atual === null ? null : String(atual), valor_novo: String(novo), origem: 'form_publico_placa' });
        }
      }

      await this.db.from('thb_alunos').update(updates).eq('id', a.id);
      if (audit.length) await this.db.from('thb_alunos_audit_log').insert(audit);
    } catch {
      // silent — promote nunca quebra o submit
    }
  }
}
