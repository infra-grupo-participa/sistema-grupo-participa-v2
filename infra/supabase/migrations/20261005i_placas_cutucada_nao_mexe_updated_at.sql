-- 20261005i — Carimbar a cutucada não pode mover updated_at nem admin_attention_at.
--
-- Medido em prod (01/10/2026): set_thb_placas_solicitacoes_updated_at (trigger trg_thb_placas_solicitacoes_updated_at,
--   BEFORE) faz sempre NEW.updated_at = now() e, no UPDATE, se qualquer coluna fora de
--   (updated_at, admin_seen_at, admin_attention_at) mudar, NEW.admin_attention_at = NEW.updated_at.
--   Logo o UPDATE de fn_placas_cutucada_reivindicar (20261005f) — e a devolução do carimbo a null quando o
--   e-mail falha — (a) zerava o "parado" do candidato e (b) acendia "nova atividade" para a equipe.
--
-- Correção SEM tocar no corpo vivo da função existente: um 2º trigger BEFORE UPDATE, que dispara DEPOIS dela
--   (Postgres dispara triggers do mesmo evento em ordem alfabética de nome; o nome novo estende o antigo).
--   Se a ÚNICA mudança da linha for cutucada_agendar_at (to_jsonb(NEW) - [updated_at, admin_attention_at,
--   cutucada_agendar_at] = mesmo no OLD, e cutucada_agendar_at de fato mudou), devolve OLD.updated_at e
--   OLD.admin_attention_at. Qualquer outra mudança junto (inclusive admin_seen_at) → comportamento atual intacto.
--   INSERT: não dispara (só UPDATE). search_path da função existente: intocado.
--
-- Guardas (aborta se falhar): trigger antigo presente, BEFORE, ROW, UPDATE; o novo dispara depois dele;
--   nenhum outro BEFORE UPDATE da tabela dispara depois do novo (poderia mover updated_at de novo).

create or replace function public.fn_placas_cutucada_preserva_atividade()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  if new.cutucada_agendar_at is distinct from old.cutucada_agendar_at
     and (to_jsonb(new) - array['updated_at', 'admin_attention_at', 'cutucada_agendar_at'])
       = (to_jsonb(old) - array['updated_at', 'admin_attention_at', 'cutucada_agendar_at']) then
    new.updated_at := old.updated_at;
    new.admin_attention_at := old.admin_attention_at;
  end if;
  return new;
end
$fn$;

revoke all on function public.fn_placas_cutucada_preserva_atividade() from public, anon, authenticated;

drop trigger if exists trg_thb_placas_solicitacoes_updated_at_z_cutucada on public.thb_placas_solicitacoes;
create trigger trg_thb_placas_solicitacoes_updated_at_z_cutucada
  before update on public.thb_placas_solicitacoes
  for each row execute function public.fn_placas_cutucada_preserva_atividade();

do $mig$
declare
  v_antigo text := 'trg_thb_placas_solicitacoes_updated_at';
  v_novo   text := 'trg_thb_placas_solicitacoes_updated_at_z_cutucada';
  v_depois text;
begin
  -- tgtype: bit0 ROW, bit1 BEFORE, bit4 UPDATE.
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.thb_placas_solicitacoes'::regclass
       and t.tgname = v_antigo and not t.tgisinternal and t.tgenabled <> 'D'
       and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16
  ) then
    raise exception '20261005i: % ausente/desabilitado ou não é BEFORE UPDATE FOR EACH ROW', v_antigo;
  end if;
  if not (v_novo collate "C" > v_antigo collate "C") then
    raise exception '20261005i: % não dispara depois de %', v_novo, v_antigo;
  end if;
  select string_agg(t.tgname, ', ') into v_depois
    from pg_trigger t
   where t.tgrelid = 'public.thb_placas_solicitacoes'::regclass
     and not t.tgisinternal and t.tgenabled <> 'D'
     and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16
     and t.tgname collate "C" > v_novo collate "C";
  if v_depois is not null then
    raise exception '20261005i: BEFORE UPDATE disparando depois do novo: %', v_depois;
  end if;
end
$mig$;

-- REVERSÃO (o carimbo da cutucada volta a mover updated_at/admin_attention_at; a função antiga nunca foi tocada):
--   drop trigger if exists trg_thb_placas_solicitacoes_updated_at_z_cutucada on public.thb_placas_solicitacoes;
--   drop function if exists public.fn_placas_cutucada_preserva_atividade();
