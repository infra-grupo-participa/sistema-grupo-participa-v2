-- Segurança lote 2b (08/10/2026, card 17tya50fqb1) — views que liam thb_alunos por fora da regra do lote 2
-- Status: APLICADA em 08/10/2026 via Management API (histórico registrado em schema_migrations); ensaio equipe=112, estranho=0
-- vw_gp_depoimentos_alunos: view sem invoker (dono postgres) → qualquer login dos 7 sistemas lia nome, e-mail,
--   telefone e CPF dos 112 alunos com depoimento. security_invoker quebraria a tela da equipe (medido: 112 → 0,
--   o RLS de gp_depoimentos não libera o operador), então o filtro vai na própria view: só a equipe (gp_eh_equipe()).
--   Leitor único: web/modules/depoimentos/ui/depoimentos-data.ts:54 (equipe @advmais, sessão).
-- vw_alunos_cancelados: authenticated tinha ALL; nenhum leitor em nenhum repo local → sem acesso pela API.
-- Reversão: 20261009061000_seg_lote2b_reversao.sql
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

create or replace view public.vw_gp_depoimentos_alunos as
 WITH depoimento_counts AS (
         SELECT gp_depoimentos.aluno_id,
            (count(*))::integer AS total_depoimentos,
            (count(*) FILTER (WHERE (COALESCE(NULLIF(TRIM(BOTH FROM gp_depoimentos.transcript), ''::text), ''::text) <> ''::text)))::integer AS depoimentos_com_transcript,
            (count(*) FILTER (WHERE (COALESCE(NULLIF(TRIM(BOTH FROM gp_depoimentos.video_url), ''::text), ''::text) <> ''::text)))::integer AS depoimentos_com_video,
            min(gp_depoimentos.testimonial_date) AS primeira_data_depoimento,
            max(gp_depoimentos.testimonial_date) AS ultima_data_depoimento
           FROM gp_depoimentos
          GROUP BY gp_depoimentos.aluno_id
        )
 SELECT d.id AS depoimento_id,
    d.aluno_id,
    a.nome AS aluno_nome,
    a.email AS aluno_email,
    a.telefone AS aluno_telefone,
    a.documento AS aluno_documento,
    a.profissao AS aluno_profissao,
    d.profissao AS depoimento_profissao,
    COALESCE(NULLIF(TRIM(BOTH FROM d.profissao), ''::text), NULLIF(TRIM(BOTH FROM a.profissao), ''::text)) AS profissao_resolvida,
    a.cidade AS aluno_cidade,
    a.estado AS aluno_estado,
    a.nivel_resultado AS aluno_nivel_resultado,
    a.turma_id AS aluno_turma_id,
    t.codigo AS turma_codigo,
    t.tipo AS turma_tipo,
    d.testimonial_date,
    d.video_url,
    d.foto_url,
    d.social_handle,
    d.drive_folder_url,
    d.drive_folder_id,
    d.transcript,
    d.source_audios_count,
    d.processing_notes,
    d.transcription_job_id,
    d.created_at AS depoimento_created_at,
    d.updated_at AS depoimento_updated_at,
    COALESCE(dc.total_depoimentos, 0) AS aluno_total_depoimentos,
    COALESCE(dc.depoimentos_com_transcript, 0) AS aluno_depoimentos_com_transcript,
    COALESCE(dc.depoimentos_com_video, 0) AS aluno_depoimentos_com_video,
    dc.primeira_data_depoimento,
    dc.ultima_data_depoimento,
    (COALESCE(NULLIF(TRIM(BOTH FROM a.email), ''::text), ''::text) = ''::text) AS falta_aluno_email,
    (COALESCE(NULLIF(TRIM(BOTH FROM a.telefone), ''::text), ''::text) = ''::text) AS falta_aluno_telefone,
    (COALESCE(NULLIF(TRIM(BOTH FROM a.documento), ''::text), ''::text) = ''::text) AS falta_aluno_documento,
    (COALESCE(NULLIF(TRIM(BOTH FROM a.profissao), ''::text), ''::text) = ''::text) AS falta_aluno_profissao,
    (COALESCE(NULLIF(TRIM(BOTH FROM a.cidade), ''::text), ''::text) = ''::text) AS falta_aluno_cidade,
    (COALESCE(NULLIF(TRIM(BOTH FROM a.estado), ''::text), ''::text) = ''::text) AS falta_aluno_estado,
    (a.nivel_resultado IS NULL) AS falta_aluno_nivel,
    (a.turma_id IS NULL) AS falta_aluno_turma,
    (COALESCE(NULLIF(TRIM(BOTH FROM d.profissao), ''::text), ''::text) = ''::text) AS falta_depoimento_profissao,
    (d.testimonial_date IS NULL) AS falta_depoimento_data,
    (COALESCE(NULLIF(TRIM(BOTH FROM d.video_url), ''::text), ''::text) = ''::text) AS falta_depoimento_video,
    (COALESCE(NULLIF(TRIM(BOTH FROM d.foto_url), ''::text), ''::text) = ''::text) AS falta_depoimento_foto,
    (COALESCE(NULLIF(TRIM(BOTH FROM d.social_handle), ''::text), ''::text) = ''::text) AS falta_depoimento_social,
    (COALESCE(NULLIF(TRIM(BOTH FROM d.drive_folder_url), ''::text), ''::text) = ''::text) AS falta_depoimento_drive,
    (COALESCE(NULLIF(TRIM(BOTH FROM d.transcript), ''::text), ''::text) = ''::text) AS falta_depoimento_transcript
   FROM (((gp_depoimentos d
     JOIN thb_alunos a ON ((a.id = d.aluno_id)))
     LEFT JOIN thb_turmas t ON ((t.id = a.turma_id)))
     LEFT JOIN depoimento_counts dc ON ((dc.aluno_id = d.aluno_id)))
  WHERE (SELECT public.gp_eh_equipe());

revoke all on public.vw_alunos_cancelados from anon, authenticated;
commit;
