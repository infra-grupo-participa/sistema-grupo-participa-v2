-- Canal de aquisição na Central de Alunos (public.thb_alunos)
-- ✅ APLICADA em 08/09/2026 no projeto "Sistema Grupo Participa" (mbvybujpkwuorhtdzcde).
--
-- ── Por que ──────────────────────────────────────────────────────────────────
-- O Victor precisa responder, na tela da Central: de onde veio cada aluno
-- (HT 12, ETHB, Acelera Holding, Imersão POA, HT ATM, Live Direto ao Ponto…),
-- se foi compra nova ou renovação, e quantos alunos novos entram por mês por
-- instrução. A tabela não tinha onde guardar isso. `origem_acesso` já tem outro
-- uso (Hotmart / Sócio-Convite / Cadastro atual) e não serve de canal.
--
-- ── O que muda ───────────────────────────────────────────────────────────────
-- Três colunas ADITIVAS. Nada existente é alterado, nenhum default, nenhuma
-- constraint: linha antiga continua válida com NULL nos três campos.
--
--   canal_aquisicao   de onde a pessoa veio. NULL = ainda não mapeado, e é assim
--                     que a lista oferece o filtro "Não atribuído".
--   tipo_entrada      'Compra nova' | 'Renovação' | 'Sócio'
--   canal_fonte       COMO o canal foi atribuído, para separar fato de regra:
--                     'Oferta é de renovação', 'oferta do checkout: …',
--                     'mapa de turma (Victor 08/09/2026)', 'É sócio…'.
--
-- ── Carga feita junto (08/09/2026) ───────────────────────────────────────────
-- 1.634 registros preenchidos a partir da planilha da Central, casando por
-- e-mail e, na falta dele, por documento — e só quando a chave apontava para UM
-- único registro. 76 continuam NULL dentro da Central (35 Aurum de oferta
-- genérica, 22 THB de turma anterior à T29, 7 OCULTO e 12 que não estão na
-- planilha).
--
-- ⚠️ Três pessoas DIFERENTES da planilha dividem e-mail com outra e caem no mesmo
-- registro do sistema (Adonai/Adam Kaminski, Rolf Brietzig/Brietzig Advocacia,
-- Patrícia Scalco/Jenifer Ponce). O desempate é o NOME do registro, não a ordem
-- da planilha — sem isso a carga grava o canal da pessoa errada.
--
-- ── Front ────────────────────────────────────────────────────────────────────
-- A tela NÃO passou a depender de fn_aluno_360_safe: alunos-data.ts lê estas
-- colunas direto de thb_alunos (mesmo padrão que já trazia data_entrada_thb),
-- e degrada em silêncio se a coluna não existir.
alter table public.thb_alunos
  add column if not exists canal_aquisicao text,
  add column if not exists tipo_entrada    text,
  add column if not exists canal_fonte     text;

comment on column public.thb_alunos.canal_aquisicao is
  'De onde o aluno veio (HT 30, Acelera Holding, ETHB, Imersão POA, Renovação, Sócio...). NULL = ainda não mapeado.';
comment on column public.thb_alunos.tipo_entrada is
  'Compra nova | Renovação | Sócio.';
comment on column public.thb_alunos.canal_fonte is
  'Como o canal foi atribuído — separa fato de inferência.';

-- Filtro por canal na lista costuma varrer a tabela inteira; o índice paga.
create index if not exists thb_alunos_canal_aquisicao_idx
  on public.thb_alunos (canal_aquisicao);
create index if not exists thb_alunos_tipo_entrada_idx
  on public.thb_alunos (tipo_entrada);
