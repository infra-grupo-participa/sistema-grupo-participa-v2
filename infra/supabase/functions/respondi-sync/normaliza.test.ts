// deno test infra/supabase/functions/respondi-sync/normaliza.test.ts --allow-read
// Prova de fidelidade: a saída do porte TS tem que ser IGUAL à de infra/scripts/respondi/carga.py para a mesma
// entrada (o `esperado` do fixture foi gerado rodando o carga.py sobre a `entrada`). Regerou o Python? Regere o fixture.
import { assertEquals } from "jsr:@std/assert@1";
import { familia, formulario, resposta } from "./normaliza.ts";

const fx = JSON.parse(await Deno.readTextFile(new URL("./normaliza.fixture.json", import.meta.url)));

Deno.test("normaliza = carga.py (formulários e respostas)", () => {
  const forms: unknown[] = [];
  const resps: unknown[] = [];
  for (const e of fx.entrada) {
    const fam = familia(e.form.name)!;
    // carga.py grava len(respondents); a Edge grava respondents_count. Aqui compara o resto do contrato.
    const { linha, flds, tc } = formulario(e.form, e.time, fam, e.respondents.length);
    forms.push(linha);
    for (const r of e.respondents) {
      const l = resposta(r, e.form.slug, flds, fam, tc);
      if (l) resps.push(l);
    }
  }
  assertEquals(forms, fx.esperado.formularios);
  assertEquals(resps, fx.esperado.respostas);
});

Deno.test("família: mesma regra do fam.py", () => {
  assertEquals(familia("NPS Encontro"), null);
  assertEquals(familia("Inclusão Sócios A3"), "socios");
  assertEquals(familia("Inscrição Workshop"), "evento");
});
