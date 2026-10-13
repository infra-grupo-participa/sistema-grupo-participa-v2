// hotmart-escritorio-webhook: webhook da Hotmart da conta ESCRITÓRIO (Soluções). Grava cada evento de compra em
// dados.hotmart_ao_vivo pela função dados.hotmart_ao_vivo_gravar (migration 20261013193000), para a venda aparecer no
// dashboard em segundos. O espelho do Financeiro (fin.hotmart_transacoes, edge hotmart-sync) continua mandando: quando
// o sync traz a transação, a linha daqui sai da leitura de dados.transacoes. Não toca fin.*, cs.* nem os outros webhooks.
//
// Segurança: verify_jwt = false (config.toml); autentica só pelo header x-hotmart-hottok, comparado em tempo constante
// com o secret HOTMART_HOTTOK_ESCRITORIO (sem secret: 503). A conexão com o banco só é criada depois do hottok conferir.
// Conta fixa ("escritorio"). 200 só depois do COMMIT; falha de gravação = 500 (a Hotmart reenvia; a gravação é
// idempotente). Log sem payload, e-mail, nome ou telefone. Regras e testes: handler.ts e handler.test.ts.
import postgres from "npm:postgres@3.4.4";
import { criarHandler } from "./handler.ts";

let cliente: ReturnType<typeof postgres> | null = null;
function banco() {
  if (!cliente) {
    const url = Deno.env.get("SUPABASE_DB_URL");
    if (!url) throw Object.assign(new Error("sem SUPABASE_DB_URL"), { code: "sem_banco" });
    cliente = postgres(url, { max: 2, prepare: false, idle_timeout: 20 });
  }
  return cliente;
}

Deno.serve(
  criarHandler({
    hottok: () => Deno.env.get("HOTMART_HOTTOK_ESCRITORIO"),
    gravar: (conta, payload) =>
      banco().begin(async (tx) => {
        // deno-lint-ignore no-explicit-any
        const [r] = await tx`select dados.hotmart_ao_vivo_gravar(${conta}, ${tx.json(payload as any)}::jsonb) as n`;
        return Number(r?.n ?? 0);
      }),
    log: (m) => console.log(`hotmart-escritorio-webhook ${m}`),
  }),
);
