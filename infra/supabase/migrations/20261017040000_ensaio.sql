-- Ensaio da 20261017040000 (roda e desfaz: begin ... rollback). Prova:
--  1) todos os pares campanha/conjunto do banco saem IGUAIS antes e depois (nenhum tem CORTES hoje);
--  2) casos sintéticos: CORTES no conjunto de ANTECIPAÇÃO (PQ, PF, formato novo com C1) vira c1/cortes;
--     CORTES fora de ANTECIPAÇÃO, em pré-captação ou como parte de outra palavra NÃO vira.
begin;
create temp table antes on commit drop as
  select c.nome cn, j.nome jn, lb.* from mkt_trafego.campanhas c join mkt_trafego.conjuntos j on j.campanha_id = c.id
  cross join lateral mkt_trafego.linha_black(c.nome, j.nome) lb;
-- 20261017040000: mkt_trafego.linha_black passa a reconhecer os CORTES da consultoria.
-- POR QUE: o Victor definiu em 16/10/2026 que os cortes da consultoria entram com a nomenclatura no CONJUNTO, dentro da
-- campanha de ANTECIPAÇÃO do C1, e que o nome do conjunto contém CORTES. Antes, o nó "Cortes das consultorias" da aba
-- Jornada ficava sem fonte. O resto da string do conjunto ainda não existe (nenhum conjunto com CORTE no banco em 16/10).
-- O QUE MUDA: só o ramo do conjunto. Conjunto com o campo/palavra CORTES em campanha cuja 1ª fase é ANTECIPACAO
-- (e que não é pré-captação nem fake live) devolve linha = 'c1', no = 'cortes'. Campanha, fase, etapa e todos os outros
-- conjuntos saem iguais (conferido no ensaio contra todos os nomes do banco).
-- Escopo: create or replace da mesma função (mesma assinatura, mesmo retorno, imutável, sem grant). Quem lê continua
-- sendo public.dados_black_trafego (20261016001100), sem mudança.
-- Reversão: 20261017040000_reversao.sql (volta o corpo da 20261016001000).

do $g$
begin
  if to_regprocedure('mkt_trafego.linha_black(text,text)') is null then
    raise exception '20261017040000: falta mkt_trafego.linha_black (aplicar a 20261016001000 antes)';
  end if;
end
$g$;

create or replace function mkt_trafego.linha_black(p_campanha text, p_conjunto text default null)
 returns table (linha text, etapa text, fase text, no text, isca text)
 language plpgsql
 immutable parallel safe
 set search_path to ''
as $function$
declare
  v_de constant text := 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç';
  v_para constant text := 'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc';
  ck text[] := '{}';
  kk text[] := '{}';
  x text;
  pre boolean := false; fake boolean := false; hoje boolean := false; dist boolean := false; c3 boolean := false;
  tem_iscas boolean := false; rmk boolean := false; base boolean := false; teaser boolean := false;
  pq boolean := false; pf boolean := false;
  outras int := 0;
  f0 text; f text; linha_c text; fase_c text;
  consult boolean := false; isca_c text; teaser_c boolean := false; manif_c boolean := false;
  cortes_c boolean := false;  -- 20261017040000
begin
  -- campanha: campos normalizados (sem acento, caixa alta, espaço simples), campo vazio descartado
  foreach x in array string_to_array(coalesce(p_campanha, ''), '|') loop
    x := btrim(regexp_replace(upper(translate(x, v_de, v_para)), '\s+', ' ', 'g'));
    if x <> '' then ck := ck || x; end if;
  end loop;

  foreach x in array ck loop
    if x in ('CPF01', 'ENTRESAFRA') then pre := true; end if;
    if x like 'LIVE FAKE%' or x like 'FAKE LIVE%' then fake := true; end if;
    if x like 'E HOJE%' then hoje := true; end if;
    if f0 is null and x in ('ANTECIPACAO', 'AQUECIMENTO', 'CAPTACAO', 'DISTRIBUICAO', 'REMARKETING', 'CARRINHO') then f0 := x; end if;
    if x = 'DISTRIBUICAO' then dist := true; end if;
    if x = 'C3' then c3 := true; end if;
    if x in ('ISCAS', 'ISCA') then tem_iscas := true; end if;
    if x = 'REMARKETING' then rmk := true; end if;
    if x in ('BASE', 'ALUNO', 'NAO ALUNO') then base := true; end if;
    if x = 'TEASER' then teaser := true; end if;
    if x = 'PQ' then pq := true; end if;
    if x = 'PF' then pf := true; end if;
    -- frente: o que não está em lista fechada nenhuma (MANIFESTO é a frente do manifesto no nome antigo)
    if x not in ('CF', 'RS', 'EF', 'BF26', 'ANTECIPACAO', 'AQUECIMENTO', 'CAPTACAO', 'DISTRIBUICAO', 'REMARKETING', 'CARRINHO',
                 'FB', 'META', 'IG', 'PQ', 'PF', 'MORNO', 'ABO', 'CBO', 'LEAD', 'THRUPLAY', 'TRAFEGO', 'ALCANCE', 'VENDA',
                 'C1', 'C2', 'C3', 'MANIFESTO')
       and x not like 'BLACK-FRIDAY%' then
      outras := outras + 1;
    end if;
  end loop;

  -- DISTRIBUICAO vence ANTECIPACAO
  f := case when f0 = 'ANTECIPACAO' and dist then 'DISTRIBUICAO' else f0 end;

  -- linha da campanha, na ordem das regras
  if pre then linha_c := 'pre_captacao';
  elsif fake then linha_c := 'fake_live';
  elsif f = 'REMARKETING' then linha_c := 'remarketing_live';
  elsif f = 'CARRINHO' then linha_c := 'carrinho';
  elsif f = 'DISTRIBUICAO' then linha_c := 'distribuicao';
  elsif f = 'ANTECIPACAO' then
    linha_c := case when pq then 'c1' when pf then 'distribuicao' when teaser then 'c1' end;
  elsif f = 'AQUECIMENTO' then
    linha_c := case when hoje then 'lembrete' when outras = 0 then 'c1' end;
  elsif f = 'CAPTACAO' then
    linha_c := case when tem_iscas then 'c2' when rmk then 'remarketing_pagina' when base or c3 then 'c3' end;
  elsif f is null then
    linha_c := case when hoje then 'lembrete' when c3 then 'c3' end;
  end if;

  -- fase da campanha
  if pre then fase_c := 'pre_captacao';
  elsif linha_c = 'distribuicao' then fase_c := 'distribuicao';
  elsif f is not null then
    fase_c := case f when 'ANTECIPACAO' then 'antecipacao' when 'AQUECIMENTO' then 'aquecimento' when 'CAPTACAO' then 'captacao'
                     when 'DISTRIBUICAO' then 'distribuicao' when 'REMARKETING' then 'remarketing' when 'CARRINHO' then 'live_carrinho' end;
  elsif fake or hoje then fase_c := 'aquecimento';
  elsif c3 then fase_c := 'captacao';
  end if;

  fase := fase_c;
  linha := linha_c;
  no := null;
  isca := null;

  if p_conjunto is not null then
    foreach x in array string_to_array(p_conjunto, '|') loop
      x := btrim(regexp_replace(upper(translate(x, v_de, v_para)), '\s+', ' ', 'g'));
      if x <> '' then kk := kk || x; end if;
    end loop;
    foreach x in array kk loop
      if x = 'CONSULTORIA' then consult := true; end if;
      if isca_c is null and x in ('CONSULTORIA', 'CHECKUP', 'FUTUROMETRO', 'FLUXOGRAMA') then isca_c := x; end if;
      if x = 'TEASER' then teaser_c := true; end if;
      if x ~ '^MANIFESTO EP[0-9][0-9]' then manif_c := true; end if;
      -- 20261017040000: cortes da consultoria = conjunto com a palavra CORTES em algum campo (Victor, 16/10/2026)
      if x ~ '(^| )CORTES( |$)' then cortes_c := true; end if;
    end loop;
    -- nomes antigos de conjunto: PQ | 00 | ... = teaser, PQ | EP01 | ... = manifesto
    if kk[1] = 'PQ' and kk[2] = '00' then teaser_c := true; end if;
    if kk[1] = 'PQ' and kk[2] ~ '^EP[0-9][0-9]$' then manif_c := true; end if;

    -- 20261017040000: cortes vivem num conjunto da campanha de ANTECIPAÇÃO do C1 (PQ, PF ou sem temperatura).
    -- O conjunto vira linha c1 e nó cortes; a fase continua a da campanha.
    if cortes_c and f0 = 'ANTECIPACAO' and not pre and not fake then
      linha := 'c1';
      no := 'cortes';
    elsif linha_c = 'c2' then
      linha := case when consult then 'consultoria' else 'iscas' end;
      no := linha;
      isca := isca_c;
    elsif linha_c = 'c1' then
      no := case when teaser_c then 'teaser' when manif_c then 'manifesto'
                 when f = 'ANTECIPACAO' then 'teaser' when f = 'AQUECIMENTO' then 'manifesto' end;
    elsif linha_c = 'distribuicao' then
      no := 'reels_pago';
    else
      no := linha_c;
    end if;
  end if;

  etapa := case when linha in ('c1', 'distribuicao') then 'C1'
                when linha in ('iscas', 'consultoria', 'c2') then 'C2'
                when linha = 'c3' then 'C3' end;
  return next;
end
$function$;

revoke all on function mkt_trafego.linha_black(text, text) from public, anon, authenticated, service_role;

do $g$
begin
  if exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
              where p.oid = 'mkt_trafego.linha_black(text,text)'::regprocedure and g.grantee <> p.proowner) then
    raise exception '20261017040000: linha_black tem grant além do dono';
  end if;
end
$g$;

select 'diferencas_banco' teste, count(*) n from antes a
  cross join lateral mkt_trafego.linha_black(a.cn, a.jn) d
 where (a.linha, a.etapa, a.fase, a.no, a.isca) is distinct from (d.linha, d.etapa, d.fase, d.no, d.isca)
union all select 'pares_banco', count(*) from antes;
select t.c, t.j, lb.* from (values
  ('CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | black-friday-2026-10', 'C1 | CORTES | público'),
  ('CF | BF26 | ANTECIPAÇÃO | FB | PF | ABO | black-friday-2026-10', 'C1 | CORTES CONSULTORIA 01 | ADV+'),
  ('CF | BF26 | C1 | ANTECIPAÇÃO | DISTRIBUIÇÃO | META | PQ | ABO | THRUPLAY | black-friday-2026-10', 'cortes | x'),
  ('CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | black-friday-2026-10', 'C1 | TEASER | público'),
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB | PF | ABO | black-friday-2026-10', 'CORTES | CONSULTORIA'),
  ('CF | BF26 | CPF01 | ANTECIPAÇÃO', 'CORTES'),
  ('CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO', 'C1 | CORTESIA | público')
) t(c, j) cross join lateral mkt_trafego.linha_black(t.c, t.j) lb;
rollback;
