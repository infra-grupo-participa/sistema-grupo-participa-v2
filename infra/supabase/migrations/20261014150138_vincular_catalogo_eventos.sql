-- APLICADA em 14/10/2026 com a versão gravada 20261014150138 (o arquivo se chamava 20261014160100; renomeado conforme o guia 6.3).
-- 20261014160100: as outras tabelas de evento passam a apontar para o catálogo oficial (fin.eventos)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2), 14/10/2026. Depende de 20261014160000.
--   Ensaio: 20261014160000_ensaio.sql. Detalhe: 20261014160000.explain.md.
--
-- POR QUE: PLANO da pessoa única, decisão 3: as 6 tabelas de evento ganham vínculo para fin.eventos, sem apagar nada.
-- O QUE FAZ (só acrescenta; colunas nullable, FK NOT VALID):
--   mkt.projetos.evento_id      -> fin.eventos(id). Preenche só o que a fonte diz: CNFMIAMI26 (id 68) = evento 101
--                                  (fin.eventos.fonte cita "mkt.projetos CNFMIAMI26"). Os outros 6 projetos não têm
--                                  linha no catálogo: ficam nulos e viram pergunta.
--   public.ht_editions.evento_id -> fin.eventos(id). Casa pelo número da edição: fin.eventos de holding_total com
--                                  codigo 'HTn' ou nome com '(HTn)'. A edição só recebe se houver exatamente 1 evento
--                                  (21 e 22 caem no evento 59 "HT21/HT22" e ficam nulas: pergunta).
--   controle.evento.evento_id    -> fin.eventos(id). lancamento-parceria-ago-2026 = evento 72 (CNHF), mesmo dia de
--                                  início (aulas_inicio = inicio = 24/08/2026) e mesma categoria de lançamento.
--   ht.cohorts.evento_id         -> fin.eventos(id). Só a coluna: as 3 linhas (1 turma, 1 modelo, 1 teste) não têm
--                                  fonte que diga o evento. Pergunta.
--   public.thb_turmas.chave      -> chave da turma (thb-tN-aaaa-mm), única. Turma não é evento do catálogo (não tem
--                                  data de início e fim; incluir turmas em fin.eventos mudaria 16 leitores do
--                                  financeiro). Fonte do mês: aba "Datas das turmas" da planilha "Alunos T1-T42
--                                  Ativação" (T1 a T37 e T17R); "T29.2 Nov/24" (nome da aba da turma na mesma
--                                  planilha); T39, T40 e T41 = mês de sale_start_at da própria thb_turmas. Ficam nulas
--                                  (pergunta): T38 (aba diz Mar/26, sale_start_at diz 12/04/2026) e A1 a A10, A8R.
--   cs.eventos                   -> NÃO recebe coluna: as 5 linhas são linhas de produto (HT, SEM, HM, CNHF, ACELERA),
--                                  não edições. Pergunta ao Maestro.
--   dados.edicoes_historico      -> já tem chave; atm-1-2026-07 é a mesma string da chave do evento 68 (vínculo pelo
--                                  próprio texto, sem coluna nova).
-- AS 5 PERGUNTAS: escala = 7 + 21 + 1 + 3 + 54 linhas; índice = único em thb_turmas.chave (54 linhas); FKs sem índice
--   nas tabelas de 1 a 21 linhas (seq scan vence); frequência = única; repetição = nenhuma;
--   reversão = 20261014160100_reversao.sql.
-- LEITORES: as tabelas são lidas por select('*') no front (ht_editions, thb_turmas): coluna nova aparece no JSON e não
--   quebra nada. O ensaio confere que nenhuma view depende de * dessas tabelas.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'fin' and table_name = 'eventos' and column_name = 'chave') then
    raise exception '20261014160100: falta 20261014160000 (fin.eventos.chave).';
  end if;
  if (select count(*) from mkt.projetos) <> 7 or (select count(*) from public.ht_editions) <> 21
     or (select count(*) from controle.evento) <> 1 or (select count(*) from ht.cohorts) <> 3
     or (select count(*) from public.thb_turmas) <> 54 then
    raise exception '20261014160100: contagem das tabelas de evento mudou. Reler.';
  end if;
  if (select sigla from mkt.projetos where id = 68) is distinct from 'CNFMIAMI26'
     or (select slug from controle.evento) is distinct from 'lancamento-parceria-ago-2026'
     or (select chave from fin.eventos where id = 72) is distinct from 'cnhf-2026-08'
     or (select chave from fin.eventos where id = 101) is distinct from 'clinica-miami-2026-12' then
    raise exception '20261014160100: premissa de vínculo não confere. Reler.';
  end if;
end
$g$;

alter table mkt.projetos   add column evento_id bigint;
alter table mkt.projetos   add constraint projetos_evento_id_fkey foreign key (evento_id) references fin.eventos(id) on delete restrict not valid;
alter table public.ht_editions add column evento_id bigint;
alter table public.ht_editions add constraint ht_editions_evento_id_fkey foreign key (evento_id) references fin.eventos(id) on delete restrict not valid;
alter table controle.evento add column evento_id bigint;
alter table controle.evento add constraint evento_evento_id_fkey foreign key (evento_id) references fin.eventos(id) on delete restrict not valid;
alter table ht.cohorts     add column evento_id bigint;
alter table ht.cohorts     add constraint cohorts_evento_id_fkey foreign key (evento_id) references fin.eventos(id) on delete restrict not valid;
alter table public.thb_turmas add column chave text
  constraint thb_turmas_chave_padrao_check check (chave is null or chave ~ '^thb-[a-z0-9]+(-[a-z0-9]+)*-[0-9]{4}-(0[1-9]|1[0-2])$');
create unique index thb_turmas_chave_key on public.thb_turmas (chave);

comment on column mkt.projetos.evento_id is 'Evento oficial do catálogo (fin.eventos). Pessoa única, 14/10/2026.';
comment on column public.ht_editions.evento_id is 'Evento oficial do catálogo (fin.eventos). Pessoa única, 14/10/2026.';
comment on column controle.evento.evento_id is 'Evento oficial do catálogo (fin.eventos). Pessoa única, 14/10/2026.';
comment on column ht.cohorts.evento_id is 'Evento oficial do catálogo (fin.eventos). Pessoa única, 14/10/2026.';
comment on column public.thb_turmas.chave is 'Chave da turma thb-tN-aaaa-mm (mês de abertura do carrinho). Pessoa única, 14/10/2026.';

update mkt.projetos set evento_id = 101 where id = 68 and evento_id is distinct from 101;
update controle.evento set evento_id = 72 where slug = 'lancamento-parceria-ago-2026' and evento_id is distinct from 72;

update public.ht_editions h
   set evento_id = m.evento_id
  from (
    select h2.id, min(e.id) evento_id
      from public.ht_editions h2
      join fin.eventos e
        on e.categoria = 'holding_total'
       and (e.codigo = 'HT' || h2.edition_number or e.nome ~ ('\mHT' || h2.edition_number || '\M'))
     group by h2.id
    having count(*) = 1
  ) m
 where h.id = m.id
   and h.evento_id is distinct from m.evento_id
   and h.edition_number not in (21, 22);   -- evento 59 junta HT21 e HT22: pergunta, não palpite

update public.thb_turmas t
   set chave = v.chave
  from (values
    ('T1', 'thb-t1-2019-10'),
    ('T2', 'thb-t2-2019-12'),
    ('T3', 'thb-t3-2020-01'),
    ('T4', 'thb-t4-2020-04'),
    ('T5', 'thb-t5-2020-06'),
    ('T6', 'thb-t6-2020-08'),
    ('T7', 'thb-t7-2020-11'),
    ('T8', 'thb-t8-2021-01'),
    ('T9', 'thb-t9-2021-03'),
    ('T10', 'thb-t10-2021-05'),
    ('T11', 'thb-t11-2021-08'),
    ('T12', 'thb-t12-2021-10'),
    ('T13', 'thb-t13-2021-12'),
    ('T14', 'thb-t14-2022-01'),
    ('T15', 'thb-t15-2022-03'),
    ('T16', 'thb-t16-2022-05'),
    ('T17', 'thb-t17-2022-07'),
    ('T17R', 'thb-t17r-2022-10'),
    ('T18', 'thb-t18-2022-12'),
    ('T19', 'thb-t19-2023-01'),
    ('T20', 'thb-t20-2023-04'),
    ('T21', 'thb-t21-2023-05'),
    ('T22', 'thb-t22-2023-08'),
    ('T23', 'thb-t23-2023-09'),
    ('T24', 'thb-t24-2023-11'),
    ('T25', 'thb-t25-2024-01'),
    ('T26', 'thb-t26-2024-03'),
    ('T27', 'thb-t27-2024-05'),
    ('T28', 'thb-t28-2024-08'),
    ('T29', 'thb-t29-2024-11'),
    ('T30', 'thb-t30-2025-02'),
    ('T31', 'thb-t31-2025-05'),
    ('T32', 'thb-t32-2025-07'),
    ('T33', 'thb-t33-2025-09'),
    ('T34', 'thb-t34-2025-10'),
    ('T35', 'thb-t35-2025-11'),
    ('T36', 'thb-t36-2026-01'),
    ('T37', 'thb-t37-2026-02'),
    ('T29.2', 'thb-t29-2-2024-11'),
    ('T39', 'thb-t39-2026-06'),
    ('T40', 'thb-t40-2026-07'),
    ('T41', 'thb-t41-2026-09')
  ) as v(codigo, chave)
 where t.codigo = v.codigo
   and t.chave is distinct from v.chave;

do $g$
begin
  if (select count(*) from public.thb_turmas where chave is not null) <> 42 then
    raise exception '20261014160100: esperava 42 turmas com chave.';
  end if;
  if (select count(*) from public.ht_editions where evento_id is not null) <> 10 then
    raise exception '20261014160100: esperava 10 edições do HT ligadas (20, 23 a 30 e 32).';
  end if;
end
$g$;
