-- APLICADA em 14/10/2026 com a versão gravada 20261014150141 (o arquivo se chamava 20261014160400; renomeado conforme o guia 6.3).
-- 20261014160400: tipo de cada oferta (sinal, saldo, integral, renovacao) para "pagou só o sinal" do HM e do Aurum
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2B), 14/10/2026. Depende de 20261014160200 (pessoas.vw_oferta).
--   Ensaio: 20261014160400_ensaio.sql (cobre 160000 a 160600). Detalhe: 20261014160400.explain.md.
--
-- POR QUE: dicionário da pessoa única, itens 1 e 8 (decisões do Victor, 14/10/2026): sinal não é compra do produto, mas
--   fica registrado (hm_so_sinal, aurum_so_sinal); reserva = sinal; renovação = tipo próprio (não é sinal).
-- O QUE FAZ:
--   1. pessoas.oferta_tipo: o tipo de uma oferta que o public.hm_product_catalog não classifica. Uma linha por oferta,
--      com a regra que deu o tipo. Nasce com as 68 ofertas de HM/Aurum cujo NOME EXATO (fin.ofertas.nome) diz o tipo
--      sem ambiguidade (regra 'nome_da_oferta'): sinal/reserva/entrada = sinal; saldo/diferença/quitação = saldo;
--      renova = renovacao; integral/pacote cheio/à vista = integral. Nome que diz dois tipos ("sinal da Renovação"),
--      que não diz nada, ou oferta sem nome no fin: NÃO entra; vai para a lista de conferência humana (356 ofertas),
--      que volta como linhas com regra 'conferencia_humana'.
--   2. pessoas.vw_oferta passa a dar o tipo nesta ordem: pessoas.oferta_tipo; senão a categoria do HM
--      (sinal e reserva = sinal, diferenca = saldo, compra_cheia = integral, renovacao = renovacao); senão nulo.
--      O catálogo do HM não é copiado (um endereço só): a view lê dele.
-- ACESSO: tabela com RLS ligada, sem policy e sem grant (só postgres), igual ao resto do schema pessoas.
-- AS 5 PERGUNTAS: escala = 68 linhas, até ~430 com a conferência; índice = PK; frequência = única + inclusões manuais;
--   repetição = nenhuma; reversão = 20261014160400_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('pessoas.vw_oferta') is null then
    raise exception '20261014160400: falta 20261014160200 (pessoas.vw_oferta).';
  end if;
  if to_regclass('pessoas.oferta_tipo') is not null then
    raise exception '20261014160400: pessoas.oferta_tipo já existe.';
  end if;
end
$g$;

create table pessoas.oferta_tipo (
  oferta_codigo text primary key check (length(oferta_codigo) between 1 and 40),
  tipo          text not null check (tipo in ('sinal', 'saldo', 'integral', 'renovacao')),
  regra         text not null check (regra in ('nome_da_oferta', 'conferencia_humana')),
  conferido_por uuid references public.perfis(id) on delete set null,
  conferido_em  timestamptz,
  criado_em     timestamptz not null default now(),
  constraint oferta_tipo_conferencia_check check ((regra = 'conferencia_humana') = (conferido_em is not null))
);
alter table pessoas.oferta_tipo enable row level security;
revoke all on pessoas.oferta_tipo from public, anon, authenticated, service_role;
comment on table pessoas.oferta_tipo is 'Tipo da oferta (sinal, saldo, integral, renovacao) quando public.hm_product_catalog não diz. '
  'regra nome_da_oferta = o nome exato da Hotmart diz o tipo; conferencia_humana = alguém conferiu (conferido_por/em).';

insert into pessoas.oferta_tipo (oferta_codigo, tipo, regra)
select v.oferta_codigo, v.tipo, 'nome_da_oferta'
  from (values
    ('0s6mlgas', 'saldo'),
    ('0wneuje4', 'renovacao'),
    ('1ftay6zh', 'sinal'),
    ('23los89e', 'saldo'),
    ('2bec4bxo', 'saldo'),
    ('2dst5ju4', 'saldo'),
    ('3taeyvt3', 'sinal'),
    ('4m2ln3iw', 'integral'),
    ('4plyg6ei', 'renovacao'),
    ('55hj74ys', 'saldo'),
    ('5qke41uk', 'renovacao'),
    ('5wpx0hji', 'renovacao'),
    ('5zbthigt', 'renovacao'),
    ('68te95i1', 'renovacao'),
    ('6h96z5wv', 'renovacao'),
    ('6lvgk55u', 'sinal'),
    ('823es8mt', 'saldo'),
    ('84tahfxy', 'saldo'),
    ('89k5nv1x', 'saldo'),
    ('9kugv3z1', 'saldo'),
    ('aldz0394', 'saldo'),
    ('bmp6tero', 'renovacao'),
    ('bzteqfhb', 'saldo'),
    ('cb3jeikd', 'sinal'),
    ('cetwlrjh', 'sinal'),
    ('d1gubzkk', 'renovacao'),
    ('e124zjn2', 'renovacao'),
    ('e4v27969', 'renovacao'),
    ('fydbjzpw', 'sinal'),
    ('gi9o06gl', 'renovacao'),
    ('hhlbnlsu', 'saldo'),
    ('hz22748u', 'sinal'),
    ('io2b58sn', 'renovacao'),
    ('ip17vk5p', 'saldo'),
    ('ipggxypl', 'saldo'),
    ('ixo7iu9u', 'renovacao'),
    ('j0eukg9z', 'sinal'),
    ('jae1if7p', 'sinal'),
    ('jiybgcmq', 'saldo'),
    ('k68nkbta', 'saldo'),
    ('l1q5624c', 'sinal'),
    ('l6qaj4o7', 'saldo'),
    ('lllte9zh', 'renovacao'),
    ('m2216g54', 'sinal'),
    ('mvkucwhf', 'renovacao'),
    ('n9rya8rz', 'saldo'),
    ('nw7zv9sq', 'sinal'),
    ('o45n4ydj', 'sinal'),
    ('ocgcc4qw', 'renovacao'),
    ('ot5o2qun', 'saldo'),
    ('otpi1sst', 'saldo'),
    ('p3d4f86p', 'sinal'),
    ('p6te2ohm', 'sinal'),
    ('r3ezbu9g', 'sinal'),
    ('shrintw5', 'saldo'),
    ('t5ra9110', 'renovacao'),
    ('tgk0ej0j', 'sinal'),
    ('tjareocy', 'sinal'),
    ('tycp384w', 'sinal'),
    ('ukhe6ubp', 'renovacao'),
    ('vq7zaz3u', 'sinal'),
    ('wcs98pas', 'renovacao'),
    ('xtq2rgis', 'integral'),
    ('yfwjy4ew', 'renovacao'),
    ('yi8ugzs7', 'saldo'),
    ('z8l9j2qt', 'sinal'),
    ('zqc1031u', 'renovacao'),
    ('zz546vjw', 'sinal')
  ) as v(oferta_codigo, tipo)
on conflict (oferta_codigo) do nothing;

create or replace view pessoas.vw_oferta with (security_invoker = true) as
select o.oferta_codigo,
       o.nome          as oferta_nome,
       o.produto_id,
       p.nome          as produto_nome,
       p.familia,
       p.conta,
       hm.categoria    as categoria_hm,
       hm.papel        as papel_hm,
       coalesce(ot.tipo,
         case hm.categoria when 'sinal' then 'sinal' when 'reserva' then 'sinal' when 'diferenca' then 'saldo'
                           when 'compra_cheia' then 'integral' when 'renovacao' then 'renovacao' end) as tipo,
       case when ot.tipo is not null then ot.regra
            when hm.categoria in ('sinal', 'reserva', 'diferenca', 'compra_cheia', 'renovacao') then 'catalogo_hm' end as regra_tipo
  from fin.ofertas o
  left join fin.produtos p on p.produto_id = o.produto_id
  left join public.hm_product_catalog hm on hm.offer_code = o.oferta_codigo
  left join pessoas.oferta_tipo ot on ot.oferta_codigo = o.oferta_codigo;
revoke all on pessoas.vw_oferta from public, anon, authenticated, service_role;

do $g$
begin
  if (select count(*) from pessoas.oferta_tipo) <> 68 then
    raise exception '20261014160400: esperava 68 ofertas classificadas pelo nome.';
  end if;
end
$g$;
