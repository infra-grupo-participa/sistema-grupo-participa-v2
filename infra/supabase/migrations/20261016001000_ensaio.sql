-- Ensaio transacional da 20261016001000: aplica a migration, confere casos, ids do Meta, gasto por linha e a reversão, e desfaz tudo no ROLLBACK final.
-- Saída: só contagens, nomes de campanha e valores em R$ (sem dado pessoal).
begin;
create temp table _z_out (em int, passo text, linha text);

-- 20261016001000: mkt_trafego.linha_black(campanha, conjunto) classifica a Black pelo padrão de nomes do Caio (guia de 15/10/2026).
-- Escopo: uma função nova (imutável, sem tabela, sem grant). Nenhuma função, tabela ou view existente é alterada;
-- mkt_trafego.etapa_black fica intacta. Quem passa a ler a função é a 20261016001100 (public.dados_black_trafego).
-- Reversão: 20261016001000_reversao.sql.
-- Regra (contrato de 16/10, decisões do Victor):
--   campanha lida por VALOR (sem acento, caixa alta, espaço simples, campo vazio descartado), não por posição;
--   fase = 1º campo que é ANTECIPACAO, AQUECIMENTO, CAPTACAO, DISTRIBUICAO, REMARKETING ou CARRINHO (DISTRIBUICAO vence ANTECIPACAO);
--   frente = o que não está nas listas fechadas do guia; os dois formatos de campanha (com e sem C1/C2/C3) valem;
--   conjunto lido por campo exato, com os nomes antigos (PQ | 00 |, PQ | EP01 |, 00 | MIX PQ |, 01 | MIX PQ |) aceitos.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('mkt_trafego.linha_black(text,text)') is not null then
    raise exception '20261016001000: mkt_trafego.linha_black(text,text) já existe';
  end if;
end
$g$;

create function mkt_trafego.linha_black(p_campanha text, p_conjunto text default null)
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
    end loop;
    -- nomes antigos de conjunto: PQ | 00 | ... = teaser, PQ | EP01 | ... = manifesto
    if kk[1] = 'PQ' and kk[2] = '00' then teaser_c := true; end if;
    if kk[1] = 'PQ' and kk[2] ~ '^EP[0-9][0-9]$' then manif_c := true; end if;

    if linha_c = 'c2' then
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
    raise exception '20261016001000: linha_black tem grant além do dono';
  end if;
end
$g$;

create temp table _casos (campanha text, conjunto text, linha text, etapa text, fase text, no text, isca text);
insert into _casos values
  ('CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | black-friday-2026-10', null, 'c1', 'C1', 'antecipacao', null, null),
  ('CF | BF26 | ANTECIPAÇÃO | FB | PF | ABO | black-friday-2026-10', null, 'distribuicao', 'C1', 'distribuicao', null, null),
  ('CF | BF26 | AQUECIMENTO | FB | PQ | ABO | black-friday-2026-10', null, 'c1', 'C1', 'aquecimento', null, null),
  ('CF | BF26 | É HOJE | AQUECIMENTO | FB | PQ | ABO | black-friday-UN2026-10', null, 'lembrete', null, 'aquecimento', null, null),
  ('CF | BF26 | AQUECIMENTO | LIVE FAKE', null, 'fake_live', null, 'aquecimento', null, null),
  ('CF | BF26 | C1 | FAKE LIVE | CONSULTORIA', null, 'fake_live', null, 'aquecimento', null, null),
  ('CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | black-friday-2026-10', null, 'c3', 'C3', 'captacao', null, null),
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | black-friday-2026-10', null, 'c2', 'C2', 'captacao', null, null),
  ('CF | BF26 | C3 | ENTRESAFRA | META | MORNO | ABO | LEAD | black-friday-2026-10', null, 'pre_captacao', null, 'pre_captacao', null, null),
  ('BF26 | CPF01 | META | IG | MORNO | ABO | VV ANTIGO | black-friday-2026-10', null, 'pre_captacao', null, 'pre_captacao', null, null),
  ('BF26 | DIST | CPF01 | META | IG | MORNO | ABO |', null, 'pre_captacao', null, 'pre_captacao', null, null),
  ('BF26 | CPF01 | META | IG | MORNO | ABO | ENGAJAMENTO 90D |', null, 'pre_captacao', null, 'pre_captacao', null, null),
  ('BF26 | CPF01 | META | IG | MORNO | ABO | VV', null, 'pre_captacao', null, 'pre_captacao', null, null),
  ('CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | black-friday-2026-10', 'C1 | TEASER | LEADS HT', 'c1', 'C1', 'antecipacao', 'teaser', null),
  ('CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | black-friday-2026-10', 'PQ | 00 | COMPRADOR ACELERA', 'c1', 'C1', 'antecipacao', 'teaser', null),
  ('CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | black-friday-2026-10', 'PQ | 00 | ENGAJOU 60D + VV75 C1 30D', 'c1', 'C1', 'antecipacao', 'teaser', null),
  ('CF | BF26 | ANTECIPAÇÃO | FB | PF | ABO | black-friday-2026-10', 'C1 | REELS | ADV+', 'distribuicao', 'C1', 'distribuicao', 'reels_pago', null),
  ('CF | BF26 | AQUECIMENTO | FB | PQ | ABO | black-friday-2026-10', 'MANIFESTO EP02 | COMPRADOR ACELERA  2.0', 'c1', 'C1', 'aquecimento', 'manifesto', null),
  ('CF | BF26 | AQUECIMENTO | FB | PQ | ABO | black-friday-2026-10', 'MANIFESTO EP02 | MQL CNHF', 'c1', 'C1', 'aquecimento', 'manifesto', null),
  ('CF | BF26 | AQUECIMENTO | FB | PQ | ABO | black-friday-2026-10', 'PQ | EP01 | LEADS HT', 'c1', 'C1', 'aquecimento', 'manifesto', null),
  ('CF | BF26 | É HOJE | AQUECIMENTO | FB | PQ | ABO | black-friday-UN2026-10', 'SEGUNDO PILAR | BASE DA CASA', 'lembrete', null, 'aquecimento', 'lembrete', null),
  ('CF | BF26 | AQUECIMENTO | LIVE FAKE', 'BASE DA CASA', 'fake_live', null, 'aquecimento', 'fake_live', null),
  ('CF | BF26 | AQUECIMENTO | LIVE FAKE', 'BF26 | ALTO ENGAJAMENTO C1', 'fake_live', null, 'aquecimento', 'fake_live', null),
  ('CF | BF26 | C1 | FAKE LIVE | CONSULTORIA', 'PQ MIX', 'fake_live', null, 'aquecimento', 'fake_live', null),
  ('CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | black-friday-2026-10', 'C3 | MIX PQ | DOR_01', 'c3', 'C3', 'captacao', 'c3', null),
  ('CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | black-friday-2026-10', 'C3 | MIX PQ | CONVITE--DIRETO_01', 'c3', 'C3', 'captacao', 'c3', null),
  ('CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | black-friday-2026-10', '00 | MIX PQ | VV C1 | DOR_01', 'c3', 'C3', 'captacao', 'c3', null),
  ('CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | black-friday-2026-10', '01 | MIX PQ | BASE DA CASA | PROVA--SOCIAL', 'c3', 'C3', 'captacao', 'c3', null),
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | black-friday-2026-10', 'VV C1 | CONSULTORIA', 'consultoria', 'C2', 'captacao', 'consultoria', 'CONSULTORIA'),
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | black-friday-2026-10', 'VV C1 | CHECKUP', 'iscas', 'C2', 'captacao', 'iscas', 'CHECKUP'),
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | black-friday-2026-10', 'VV C1 | FLUXOGRAMA', 'iscas', 'C2', 'captacao', 'iscas', 'FLUXOGRAMA'),
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | black-friday-2026-10', 'VV C1 | FUTUROMETRO', 'iscas', 'C2', 'captacao', 'iscas', 'FUTUROMETRO'),
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | black-friday-2026-10', 'QUENTE DIGITAL | FLUXOGRAMA', 'iscas', 'C2', 'captacao', 'iscas', 'FLUXOGRAMA'),
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | black-friday-2026-10', 'VV C1 | ISCA NOVA SEM LISTA', 'iscas', 'C2', 'captacao', 'iscas', null),
  ('CF | BF26 | C3 | ENTRESAFRA | META | MORNO | ABO | LEAD | black-friday-2026-10', '00 -  Semelhante (1% to 2%) - HT_Total', 'pre_captacao', null, 'pre_captacao', 'pre_captacao', null),
  ('CF | BF26 | C3 | ENTRESAFRA | META | MORNO | ABO | LEAD | black-friday-2026-10', '01 - CPF01 VV25%', 'pre_captacao', null, 'pre_captacao', 'pre_captacao', null),
  ('BF26 | CPF01 | META | IG | MORNO | ABO | VV ANTIGO | black-friday-2026-10', '01 - ENGAJAMENTO 90D', 'pre_captacao', null, 'pre_captacao', 'pre_captacao', null),
  ('CF | BF26 | C1 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY | black-friday-2026-10', null, 'c1', 'C1', 'antecipacao', null, null),
  ('CF | BF26 | C1 | ANTECIPAÇÃO | DISTRIBUIÇÃO | META | PQ | ABO | THRUPLAY | black-friday-2026-10', null, 'distribuicao', 'C1', 'distribuicao', null, null),
  ('CF | BF26 | C1 | AQUECIMENTO | MANIFESTO | META | PQ | ABO | THRUPLAY | black-friday-2026-10', null, 'c1', 'C1', 'aquecimento', null, null),
  ('CF | BF26 | É HOJE | SEGDO PILAR | META | PQ | ABO | TRAFEGO | black-friday-UN2026-10', null, 'lembrete', null, 'aquecimento', null, null),
  ('CF | BF26 | LIVE |', null, null, null, null, null, null),
  ('CF | BF26 | C3 | CAPTAÇÃO | META | PQ | ABO | LEAD | black-friday-2026-10', null, 'c3', 'C3', 'captacao', null, null),
  ('CF | BF26 | C3 | CAPTAÇÃO | META | PQ | ABO | LEAD | V1 | black-friday-2026-10', null, 'c3', 'C3', 'captacao', null, null),
  ('CF | BF26 | C2 | ISCAS | CAPTAÇÃO | META | PQ | ABO | LEAD | black-friday-2026-10', null, 'c2', 'C2', 'captacao', null, null),
  ('CF | BF26 | C2 | ISCAS | CAPTAÇÃO | META | PQ | ABO | LEAD | black-friday-2026-10', 'VV C1 | CONSULTORIA', 'consultoria', 'C2', 'captacao', 'consultoria', 'CONSULTORIA'),
  ('CF | BF26 | C3 | META | PQ | ABO | LEAD', null, 'c3', 'C3', 'captacao', null, null),
  ('CF | BF26 | CAPTAÇÃO | ALUNO | FB | PQ | ABO | LEAD | black-friday-2026-10', 'C3 | ALUNOS E COMPRADORES', 'c3', 'C3', 'captacao', 'c3', null),
  ('CF | BF26 | CAPTAÇÃO | NAO ALUNO | FB | PQ | ABO | LEAD | black-friday-2026-10', 'C3 | LEADS DA CASA', 'c3', 'C3', 'captacao', 'c3', null),
  ('CF | BF26 | CAPTAÇÃO | REMARKETING | FB | PQ | ABO | LEAD | black-friday-2026-10', null, 'remarketing_pagina', null, 'captacao', null, null),
  ('CF | BF26 | CAPTAÇÃO | REMARKETING | FB | PQ | ABO | LEAD | black-friday-2026-10', 'RMK | VISITOU SEM LEAD 7D', 'remarketing_pagina', null, 'captacao', 'remarketing_pagina', null),
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | black-friday-2026-10', 'QUENTE DIGITAL | FLUXOGRAMA', 'iscas', 'C2', 'captacao', 'iscas', 'FLUXOGRAMA'),
  ('CF | BF26 | REMARKETING | FB | PQ | ABO | black-friday-2026-10', 'É HOJE 0311', 'remarketing_live', null, 'remarketing', 'remarketing_live', null),
  ('CF | BF26 | CARRINHO | FB | PQ | ABO | black-friday-2026-10', 'VISITOU CHECKOUT', 'carrinho', null, 'live_carrinho', 'carrinho', null),
  ('cf|bf26|captacao|iscas|fb', 'vv c1 | consultoria', 'consultoria', 'C2', 'captacao', 'consultoria', 'CONSULTORIA'),
  ('CF |  BF26 |  CAPTAÇÃO  | BASE ||', null, 'c3', 'C3', 'captacao', null, null),
  ('CF | BF26 | CAPTAÇÃO | FRENTE NOVA | FB', null, null, null, 'captacao', null, null),
  ('CF | BF26 | AQUECIMENTO | FRENTE NOVA | FB', null, null, null, 'aquecimento', null, null),
  ('CF | BF26 | ANTECIPAÇÃO | FB', null, null, null, 'antecipacao', null, null),
  ('CF | BF26 | OUTRA COISA', null, null, null, null, null, null),
  ('', '', null, null, null, null, null),
  (null, null, null, null, null, null, null);

create temp table _ids (campanha_externa text, linha text);
insert into _ids values
  ('120255892164920221', 'c1'),
  ('120256069854270221', 'distribuicao'),
  ('120255950674590221', 'c1'),
  ('120256079490570221', 'lembrete'),
  ('120256084721860221', 'fake_live'),
  ('120256045999340221', 'fake_live'),
  ('120256045812000221', 'c3'),
  ('120256028497250221', 'c3'),
  ('120256038798760221', 'c2'),
  ('120255408390470221', 'pre_captacao'),
  ('120255395494830221', 'pre_captacao'),
  ('120255394769730221', 'pre_captacao'),
  ('120255394583660221', 'pre_captacao'),
  ('120255393836500221', 'pre_captacao');

-- 1. casos unitários (nome atual, antigo, previsto, sintético, vazio e não reconhecido)
insert into _z_out
select 1, 'casos_total', count(*)::text from _casos
union all
select 1, 'casos_falhos', count(*)::text
  from _casos v cross join lateral mkt_trafego.linha_black(v.campanha, v.conjunto) l
 where (l.linha, l.etapa, l.fase, l.no, l.isca) is distinct from (v.linha, v.etapa, v.fase, v.no, v.isca);
insert into _z_out
select 2, 'falho: ' || left(coalesce(v.campanha, '<null>') || ' || ' || coalesce(v.conjunto, '<null>'), 120),
       'esperado ' || concat_ws('/', v.linha, v.etapa, v.fase, v.no, v.isca) || ' veio ' || concat_ws('/', l.linha, l.etapa, l.fase, l.no, l.isca)
  from _casos v cross join lateral mkt_trafego.linha_black(v.campanha, v.conjunto) l
 where (l.linha, l.etapa, l.fase, l.no, l.isca) is distinct from (v.linha, v.etapa, v.fase, v.no, v.isca);

-- 2. seção 2 do guia: a linha de cada campanha pelo ID do Meta
insert into _z_out
select 3, 'ids_guia_conferidos', count(*)::text
  from _ids i join mkt_trafego.campanhas c on c.campanha_externa = i.campanha_externa
union all
select 3, 'ids_guia_fora_do_banco', count(*)::text
  from _ids i where not exists (select 1 from mkt_trafego.campanhas c where c.campanha_externa = i.campanha_externa)
union all
select 3, 'ids_guia_linha_diferente', count(*)::text
  from _ids i join mkt_trafego.campanhas c on c.campanha_externa = i.campanha_externa
  cross join lateral mkt_trafego.linha_black(c.nome) l
 where l.linha is distinct from i.linha;

-- 3. a função não quebra em nenhum nome do banco (uma linha por chamada)
insert into _z_out
select 4, 'campanhas_no_banco', count(*)::text from mkt_trafego.campanhas
union all
select 4, 'campanhas_com_linha_nula_ou_nao', count(*)::text || ' linhas devolvidas' from mkt_trafego.campanhas c cross join lateral mkt_trafego.linha_black(c.nome) l
union all
select 4, 'conjuntos_no_banco', count(*)::text from mkt_trafego.conjuntos
union all
select 4, 'conjuntos_linhas_devolvidas', count(*)::text
  from mkt_trafego.conjuntos j join mkt_trafego.campanhas c on c.id = j.campanha_id cross join lateral mkt_trafego.linha_black(c.nome, j.nome) l;

-- 4. gasto por linha da BF26 (campanha, BRL, 01/09 a 14/10) e campanha com gasto sem linha
insert into _z_out
select 5, 'gasto_linha ' || coalesce(l.linha, '<sem classificação>'), to_char(round(sum(d.gasto), 2), 'FM999G999D00')
  from mkt_trafego.campanhas c
  join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
  join mkt_trafego.desempenho_dia d on d.campanha_id = c.id and d.dia between date '2026-09-01' and date '2026-10-14'
  cross join lateral mkt_trafego.linha_black(c.nome) l
 where (c.projeto_id = 4 or (c.projeto_id is null and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = 'BF26')))
 group by l.linha;
insert into _z_out
select 6, 'campanha_com_gasto_sem_linha', coalesce(string_agg(x.nome || ' = ' || x.g, '; '), 'nenhuma')
  from (select c.nome, round(sum(d.gasto), 2)::text as g
          from mkt_trafego.campanhas c
          join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
          join mkt_trafego.desempenho_dia d on d.campanha_id = c.id
          cross join lateral mkt_trafego.linha_black(c.nome) l
         where (c.projeto_id = 4 or (c.projeto_id is null and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = 'BF26'))) and l.linha is null
         group by c.nome having sum(d.gasto) > 0) x;
insert into _z_out
select 7, 'conjunto_com_gasto_sem_no', coalesce(string_agg(x.nome || ' = ' || x.g, '; '), 'nenhum')
  from (select j.nome, round(sum(d.gasto), 2)::text as g
          from mkt_trafego.conjuntos j
          join mkt_trafego.campanhas c on c.id = j.campanha_id
          join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
          join mkt_trafego.anuncios a on a.conjunto_id = j.id
          join mkt_trafego.desempenho_anuncio_dia d on d.anuncio_id = a.id
          cross join lateral mkt_trafego.linha_black(c.nome, j.nome) l
         where (c.projeto_id = 4 or (c.projeto_id is null and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = 'BF26'))) and l.no is null
         group by j.nome having sum(d.gasto) > 0) x;

-- 5. propriedades da função: imutável, sem grant além do dono
insert into _z_out
select 8, 'volatilidade', p.provolatile::text || ' (i = imutável)' from pg_proc p where p.oid = 'mkt_trafego.linha_black(text,text)'::regprocedure
union all
select 8, 'grants_alem_do_dono', count(*)::text
  from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
 where p.oid = 'mkt_trafego.linha_black(text,text)'::regprocedure and g.grantee <> p.proowner;

-- 6. custo: a função sobre todas as campanhas e sobre todos os conjuntos do banco
do $t$
declare t0 timestamptz; n int; ms numeric;
begin
  t0 := clock_timestamp();
  select count(*) into n from mkt_trafego.campanhas c cross join lateral mkt_trafego.linha_black(c.nome) l;
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  insert into _z_out values (8, 'tempo_todas_as_campanhas', n || ' chamadas em ' || ms || ' ms');
  t0 := clock_timestamp();
  select count(*) into n from mkt_trafego.conjuntos j join mkt_trafego.campanhas c on c.id = j.campanha_id cross join lateral mkt_trafego.linha_black(c.nome, j.nome) l;
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  insert into _z_out values (8, 'tempo_todos_os_conjuntos', n || ' chamadas em ' || ms || ' ms');
end
$t$;

-- 7. reversão ensaiada
-- Reversão da 20261016001000: remove mkt_trafego.linha_black(text, text).
-- Antes, reverter a 20261016001100 (public.dados_black_trafego passa a chamar a função); a guarda abaixo para se alguém ainda a usa.
-- Depois: delete from supabase_migrations.schema_migrations where version = '20261016001000';
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if exists (select 1 from pg_proc p
              where p.prokind = 'f' and p.oid <> 'mkt_trafego.linha_black(text,text)'::regprocedure
                and p.prosrc like '%linha_black%') then
    raise exception '20261016001000 reversão: ainda há função que chama linha_black; reverter a 20261016001100 antes';
  end if;
end
$g$;

drop function mkt_trafego.linha_black(text, text);

insert into _z_out select 9, 'apos_reversao_funcao_existe', (to_regprocedure('mkt_trafego.linha_black(text,text)') is not null)::text;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
