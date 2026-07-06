import type { SupabaseClient } from '@supabase/supabase-js';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';

// Gateway do fluxo PÚBLICO de placa — porta de placa-public.php.
// Usa service_role (token UUID é a fronteira de segurança), como no PHP legado.

const PUBLIC_FIELDS =
  'id,token,status,step_index,auditoria_step,nome,email,telefone,turma,profissao,telefone_profissional,youtube_url,site_profissional,instagram_url,facebook_url,interesse,espaco_instrucao,nivel,nivel_anterior,ciclo,faturamento_declarado,proof_url,declaracao_url,cep,logradouro,numero,complemento,bairro,cidade,estado_uf,pais,documento_nf,entrevista_data,entrevista_hora,entrevista_link,meet_link,codigo_rastreio,motivo_retorno,regularizacao_pendente';

type Row = Record<string, unknown>;

/** Escapa curingas de (i)like — o valor vem do usuário e deve casar literal. */
const escapeLike = (s: string) => s.replace(/[\\%_]/g, '\\$&');

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
    // E-mail casa case-insensitive: `.eq` deixava "Maria@X.com" e "maria@x.com" coexistirem
    // como duas solicitações da mesma pessoa. Escapamos %/_ por serem curinga do (i)like.
    let q = this.db.from('thb_placas_solicitacoes').select('token,status');
    q = field === 'email' ? q.ilike('email', escapeLike(value)) : q.eq(field, value);
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
      .ilike('email', escapeLike(email))
      .eq('documento_nf', documento)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    return (data as Row) ?? null;
  }

  /**
   * Refazer processo (subiu de nível): arquiva o ciclo concluído e reseta a MESMA linha
   * (token/sessão preservados) via RPC atômica. Retorna a solicitação já resetada, ou um
   * erro tipado. Só permitido para status 'concluido' (a RPC garante).
   */
  async refazer(token: string): Promise<{ ok: true; row: Row } | { ok: false; reason: string }> {
    const { error } = await this.db.rpc('fn_placas_refazer', { p_token: token });
    if (error) {
      const msg = String(error.message ?? '');
      if (msg.includes('nao_concluido')) return { ok: false, reason: 'nao_concluido' };
      if (msg.includes('nivel_maximo')) return { ok: false, reason: 'nivel_maximo' };
      if (msg.includes('nao_encontrada')) return { ok: false, reason: 'nao_encontrada' };
      return { ok: false, reason: 'erro' };
    }
    const row = await this.loadByToken(token);
    if (!row) return { ok: false, reason: 'nao_encontrada' };
    return { ok: true, row };
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

  /** Acende a notificação do admin (não-visto + topo da fila): ação relevante do aluno. */
  async markClientAttention(id: string): Promise<void> {
    await this.db
      .from('thb_placas_solicitacoes')
      .update({ admin_seen_at: null, admin_attention_at: new Date().toISOString() })
      .eq('id', id);
  }

  /** Linha mínima para validar um upload (status + flag de correção). */
  async loadForUpload(token: string): Promise<{ id: string; status: string; step_index: number; regularizacao_pendente: boolean | null } | null> {
    const { data } = await this.db
      .from('thb_placas_solicitacoes')
      .select('id,status,step_index,regularizacao_pendente')
      .eq('token', token)
      .limit(1)
      .maybeSingle();
    return (data as { id: string; status: string; step_index: number; regularizacao_pendente: boolean | null }) ?? null;
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
      .select('token,status,step_index,auditoria_step,entrevista_data,entrevista_hora')
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

  /** Matching canônico com a central (e-mail tem prioridade sobre documento). */
  async centralMatch(email: string, documento: string): Promise<{ aluno_id: string; match_por: string; espaco_instrucao: string | null } | null> {
    const { data } = await this.db.rpc('fn_central_match', { p_email: email, p_documento: documento });
    const row = Array.isArray(data) ? (data[0] as { aluno_id: string; match_por: string; espaco_instrucao: string | null } | undefined) : undefined;
    return row ?? null;
  }

  /**
   * Vínculo antecipado com a central logo no cadastro (etapa 1): grava o resultado do
   * matching (central_match) e o aluno_id quando existe — o admin enxerga desde o rascunho
   * quem é aluno da base e quem não tem registro (possível ex-aluno).
   */
  async vincularCentral(token: string, email: string, documento: string): Promise<void> {
    try {
      const m = await this.centralMatch(email, documento);
      const patch: Row = { central_match: m?.match_por ?? 'nenhum' };
      if (m?.aluno_id) patch.aluno_id = m.aluno_id;
      await this.db.from('thb_placas_solicitacoes').update(patch).eq('token', token);
    } catch {
      /* melhor-esforço — vínculo se refaz no submit */
    }
  }

  /**
   * Promove dados da solicitação para thb_alunos (apenas no submit final).
   * Matching por e-mail OU documento; a central é fonte de verdade para espaco_instrucao
   * (corrige o que o aluno digitou errado no formulário). Campos de contato fluem
   * solicitação→aluno só se atualizado_por IS NULL. Não-crítico: erros são engolidos.
   */
  async promoteToAluno(token: string, payload: Row): Promise<void> {
    try {
      const email = String(payload.email ?? '').trim();
      const documento = String(payload.documento_nf ?? '').trim();
      if (!email && !documento) return;

      const { data: sol } = await this.db
        .from('thb_placas_solicitacoes')
        .select('id, espaco_instrucao')
        .eq('token', token)
        .limit(1)
        .maybeSingle();
      const solicitacaoId = (sol as Row)?.id;
      if (!solicitacaoId) return;

      const m = await this.centralMatch(email, documento);
      if (!m) {
        // Sem registro na base — pode se tratar de ex-aluno; o admin vê o alerta na fila.
        await this.db.from('thb_placas_solicitacoes').update({ central_match: 'nenhum' }).eq('id', solicitacaoId);
        return;
      }

      // Vínculo + inteligência central→solicitação: espaço de instrução da central corrige
      // o informado no formulário (fonte de verdade é o cadastro oficial).
      const solPatch: Row = { central_match: m.match_por, aluno_id: m.aluno_id };
      const espacoForm = String((sol as Row)?.espaco_instrucao ?? payload.espaco_instrucao ?? '');
      if (m.espaco_instrucao && espacoForm && m.espaco_instrucao !== espacoForm) {
        solPatch.espaco_instrucao = m.espaco_instrucao;
        await this.db.from('thb_system_events').insert({
          tipo: 'business',
          fonte: 'form_publico_placa',
          titulo: 'Espaço de instrução corrigido pela central',
          detalhe: { solicitacao_id: solicitacaoId, informado: espacoForm, central: m.espaco_instrucao },
          aluno_id: m.aluno_id,
        });
      }
      await this.db.from('thb_placas_solicitacoes').update(solPatch).eq('id', solicitacaoId);

      const { data: aluno } = await this.db
        .from('thb_alunos')
        .select(
          'id,atualizado_por,placa_solicitacao_id,telefone,documento,cep,cidade,estado,bairro,pais,endereco_logradouro,endereco_numero,endereco_complemento,profissao,telefone_profissional,instagram_url,youtube_url,site_profissional,link_facebook',
        )
        .eq('id', m.aluno_id)
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
