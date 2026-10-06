# Convergência pessoas × CRM (F0): o que veio da branch victor

> 05/10/2026. Registro, não pedido de validação. A proposta da branch `victor` (migration `20261005o`, nunca aplicada)
> era visão inicial e pode ser sobrescrita. Resultado: `infra/supabase/migrations/20261005r_pessoas_e_crm_fundacao.sql`
> (+ `_ensaio.sql`, `.explain.md`). **NÃO APLICADA — aguardando ok do Arthur.**

## 1. Aproveitado (schema `pessoas`)

| Peça da 20261005o | Como ficou |
|---|---|
| Schema `pessoas` como base única da central (lead = aluno = comprador) | Mantido |
| Aluno e comprador por **referência** (`aluno_id`, `comprador_id`), nunca cópia; ficha lê na hora | Mantido |
| `ref` opaca (`pe_` + 32 hex) para outros sistemas (`mkt_web.visitantes.lead_ref`) | Mantido |
| `identificadores`, `origens` (mkt.projetos/paginas, campanha no padrão, UTMs), `eventos`, `revisao`, `acessos` | Mantidos (ajustes abaixo) |
| `pessoas.config` (`areas_leitura/edicao/contato`) + `pode_ver/pode_editar/pode_ver_contato` sobre `gp_is_admin` | Mantido, com `coalesce` em toda guarda |
| Normalização (`norm_email`, `norm_telefone`, `norm_nome`, `norm_cep`, `chave_nome_cep`, `nomes_compativeis`, máscaras) | Mantida |
| `registrar` (entrada única formulário/CRM/importação), `pessoa_do_aluno/comprador`, `garantir` | Mantidos |
| `public.pessoas_*` (meu_acesso, buscar, ficha, cadastrar, registrar_lead só service_role, revisao_listar/decidir) | Mantidas, reescritas onde indicado |
| Padrão de ensaio (linhas OK/ERRADO, papéis simulados, dados fictícios) | Mantido |

## 2. Mudado, e por quê

| Mudança | Regra |
|---|---|
| **Casamento por e-mail primeiro.** Cascata documento → telefone → e-mail → nome+CEP virou: e-mail → (sem e-mail) telefone → pessoa nova | Manual §7 "casar pessoa por e-mail, nunca por nome ou CPF"; D1 |
| **CPF/documento fora**: sai de `identificadores`, cascata, `anexar`, `dados`, ficha, busca, máscara; `doc_valido`, `norm_documento`, `pode_ver_doc` e a dependência de `gp_pode_ver_cpf` removidos | Manual §6/§7, LGPD; D1 |
| **Telefone = `controle.fone_key`** (a função dos índices vivos), não chave própria | Manual §7 "chave sai da função que grava"; D2 |
| Telefone só casa sozinho **sem e-mail e com exatamente 1 candidato** de nome compatível; telefone igual + e-mail diferente → revisão | backend-arquitetura §2.3. Medido: 809 chaves de fone repetidas em compradores |
| Nome+CEP e só-nome **nunca casam** (só abrem revisão) | Manual §7 |
| **Performance**: `casar` aplicava normalização linha a linha em `thb_alunos`/`compradores` (Seq Scan; telefone em compradores = 420 ms). Agora valor normalizado na variável × expressão exata do índice; índice novo `ix_compradores_fone_key`; nome por trigram. Resolver: 0,7–7 ms | Manual §5 |
| **Mescla = alias**: `mesclar` movia identificadores/origens/eventos/negócios e apagava duplicados. Agora só `situacao='mesclada'` + `mesclada_em`; leituras usam `pessoas.atual()`/`pessoas.grupo()`; `pessoas_mescla_desfazer` limpa | Manual §10 "alias, não merge destrutivo" |
| Revisão com motivos novos (`email_conflito`, `telefone_email_diferente`, `telefone_varios`); `on delete cascade` virou `restrict` | Nunca apagar |
| Busca reescrita por ramos com índice (union), sem OR que derruba o índice | Manual §5 |

## 3. Descartado

| Peça | Destino |
|---|---|
| `crm.pipelines` (4 fixos), `crm.etapas`, `crm.motivos_perda`, `crm.negocios`, `crm.historico`, `crm.validar_movimento/msg_movimento` | Saem. Os 4 pipelines (ativação, vendas, recuperação de carrinho, recuperação de venda) viram **modelos de funil** na F1 (`crm.funil`/`crm.etapa_funil` configuráveis, backend-arquitetura §3.4). `historico` → `crm.log` gravado por trigger |
| `public.crm_config`, `crm_negocios_listar`, `crm_negocio_criar/mover/editar/historico`, `crm_etapa_salvar`, `crm_motivo_salvar` | Viram as RPCs do contrato `web/modules/comercial/application/ports.ts` (backend-arquitetura §4.3/§7), F1/F2 |
| `pessoas.acessos` com ações `crm_*`; `negocios_abertos` na busca; seção `negocios` da ficha | Saem da F0 (dependiam de `crm.negocios`); voltam pela F1 |
| Gancho `externo_tipo = 'cs.contatos_hm'` | Fora; decisão D4 (coexistir com `cs.contatos`) |
| Migration `20261005o_*` (3 arquivos) | **Não vai para a main**: colide com `20261005r` (cria os mesmos schemas) |

`crm` da F0 = modelo do Arthur: `config` (kill-switches), `vendedor` (sem cadastro real), `log` append-only +
`tg_log()`, `eh_gestor/eh_vendedor/eh_comercial` (D5 admin/dev = gestor; D6 aplicado nas policies da F1).
A `crm.pessoa`/`pessoa_chave`/`pessoa_sugestao` do desenho original é substituída por `pessoas.*`; atributos
comerciais (dono, tags, score, opt-out) entram na F1 numa tabela `crm.*` com FK para `pessoas.pessoas`.

## 4. Front: a branch arthur prevalece

Ao juntar na main, o módulo `web/modules/comercial` é o da branch `arthur` (contrato `application/ports.ts`).
Arquivos da branch `victor`:

| Arquivo (victor) | Destino |
|---|---|
| `domain/identidade.ts` + `.test.ts` | **Absorver** as regras de normalização no domínio do arthur, já sem documento e com `chaveTelefone` = `fone_key` (DDD + 8; D2). O resto descarta |
| `domain/pessoas.ts` + `.test.ts` | **Absorver** os tipos de retorno de `pessoas_buscar/ficha/revisao_listar` no futuro `SupabaseComercialRepository` (sem `documento`, sem `negocios_abertos`; com `aliases`, `comprador_ids`) |
| `ui/PessoasPainel.tsx`, `ui/FichaPessoa.tsx`, `ui/RevisaoPainel.tsx` | **Absorver** como abas dentro de Contatos (`ui/contatos/`), reescritas sobre o port. Revisão ganha "desfazer mescla" |
| `domain/crm.ts` + `.test.ts` | Descartar (regras de pipeline fixo; o arthur tem `domain/funis.ts`) |
| `infrastructure/comercial-data.ts`, `infrastructure/demo.ts` | Descartar (chamavam `public.crm_*` da 20261005o; o arthur usa `MockComercialRepository` + futuro repositório Supabase) |
| `ui/ComercialClient.tsx`, `ui/CrmPainel.tsx` | Descartar (substituídos por `ui/funil/` e demais telas do arthur) |
| `web/app/(admin)/comercial/page.tsx`, `layout.tsx` | Ficam os do arthur (14 rotas). Conferir só a trava de acesso do `layout.tsx` do victor (admin/dev) |
| `infra/supabase/migrations/20261005o_*` | Descartar (ver §3) |
| `docs/central-de-dados.md` (trechos de pessoas/CRM) | Atualizar para apontar para a 20261005r |
| `web/shared/ui/shell/Sidebar.tsx` (BASE_MARKETING) | Fora do Comercial; não tratado aqui |

## 5. Em aberto (decisão do Arthur)

1. Criar `ix_compradores_fone_key` dentro da migration (lock de escrita curto em `compradores`) ou antes com
   `create index concurrently`?
2. Mescla de duas pessoas com **compradores diferentes** é permitida (alias guarda os dois); dois **alunos**
   diferentes continua recusado (conferência na Central de Alunos). Ok?
3. `garantir` cria linha de referência para aluno/comprador que vira candidato de revisão. Ok, ou só criar quando a
   pessoa decidir "mesma"?
4. Backfill (alunos e compradores como pessoas) fica fora da F0. Quando e como?
