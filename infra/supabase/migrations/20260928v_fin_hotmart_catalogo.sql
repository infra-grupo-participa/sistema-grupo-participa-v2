-- 20260928v — Catálogo de produtos da Hotmart (27/09/2026). Pedido do João: "não pode deixar nada fora do sistema".
-- O espelho só puxa os produtos listados em fin.produtos; produto que vende e não está lá fica invisível. Esta tabela
-- guarda TODOS os produtos da conta (GET /products/api/v1/products, só leitura), gravados pela Edge Function
-- hotmart-sync no modo {"catalogo": true}. Com ela dá para ver o que existe e não é espelhado — e achar os produtos
-- do seminário (Sessão de Viabilidade, Croqui Estrutural, Holding).
create table if not exists fin.hotmart_catalogo (
  produto_id text primary key,
  nome text,
  status text,
  formato text,
  ucode text,
  criado_na_hotmart timestamptz,
  bruto_json jsonb,
  visto_em timestamptz not null default now()
);
alter table fin.hotmart_catalogo enable row level security;
revoke all on fin.hotmart_catalogo from public, anon, authenticated;

-- Atualiza o catálogo uma vez por dia (junto com a releitura de 60 dias).
select cron.schedule('fin-hotmart-catalogo', '31 3 * * *', $$
  select net.http_post(
    url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/hotmart-sync',
    headers := jsonb_build_object('Content-Type','application/json','x-sync-chave',
      (select decrypted_secret from vault.decrypted_secrets where name = 'fin_hotmart_sync_chave')),
    body := '{"catalogo": true}'::jsonb, timeout_milliseconds := 150000) $$);
