# Arquitetura — sistema-grupo-participa (web)

Next.js 16 (App Router) + Supabase, organizado como **monólito modular** sob princípios de
**Clean Architecture**. O objetivo é manter a lógica de negócio independente de framework e de
fornecedor (Supabase), testável isoladamente e escalável por feature.

## Regra de dependência (o que importa o quê)

```
            ┌─────────────────────────────────────────────┐
 presentation (app/, *.ui)  ──►  application  ──►  domain  │
            │                         ▲                     │
            │                         │ (ports/interfaces)  │
            └──── infrastructure ─────┘                     │
                  (adapters)                                │
```

- **domain** não importa NADA (sem Next, sem Supabase). Só tipos e regras puras.
- **application** importa só `domain`. Define **ports** (interfaces) do que precisa do mundo externo.
- **infrastructure** implementa os ports (adapters): Supabase, Resend, Groq, Google Drive… Importa `domain` + `application`.
- **presentation** (rotas/route handlers/React) chama **casos de uso** da `application`, resolvidos por um **composition root**. Nunca acessa Supabase direto para regra de negócio.

A direção das setas nunca se inverte: o núcleo (domain/application) não conhece detalhes de I/O.

## Layout de pastas

```
web/
  app/                      ← Next.js: rotas, Server Components, Route Handlers (camada fina)
  shared/                   ← núcleo transversal a todas as features
    domain/                 ← entidades/regras puras compartilhadas (ex.: auth, nivel-resultado)
    application/            ← casos de uso + ports transversais
    infrastructure/         ← clients Supabase, config/env, logger, adapters compartilhados
    composition/            ← composition root (DI): wira adapters → casos de uso
    ui/                     ← design system + app shell (Sidebar, Header) + config de navegação
  modules/                  ← uma pasta por feature (vertical slice), mesma estrutura interna
    <feature>/
      domain/               ← entidades/value objects/regras da feature
      application/          ← casos de uso + ports da feature
      infrastructure/       ← repositórios/adapters (Supabase, APIs externas)
      ui/                   ← componentes/hooks React da feature
```

Features previstas: `placas`, `alunos`, `depoimentos`, `usuarios`. Cada uma é um *slice* fechado;
o acoplamento entre módulos acontece só via `application` (casos de uso) ou `domain` de `shared`.

## Ports & Adapters (inversão de dependência)

Casos de uso dependem de **interfaces** declaradas na própria `application`, não de Supabase:

```ts
// modules/placas/application/ports.ts
export interface PlacaAuditoriaRepository {
  findByAlunoId(id: string): Promise<PlacaAuditoria | null>;
  save(a: PlacaAuditoria): Promise<void>;
}
// modules/placas/infrastructure/supabase-placa-auditoria.repository.ts  (implementa o port)
```

Benefícios: trocar Supabase por outro backend, mockar em teste (Vitest), e isolar a complexidade
de RLS num único lugar.

## Permissão e segurança (duas camadas, ambas preservadas do legado)

1. **Domínio de permissão** (`shared/domain/auth`): porta fiel do modelo canônico LGPD v2 do
   `auth.js` (cargo dev/admin/gestor/operador/visualizador + setores/funções + máscara de CPF).
   Funções puras → usadas para *gating* de UI e de casos de uso.
2. **RLS do banco** (fonte de verdade real): por padrão usamos o client Supabase **com a sessão do
   usuário** (cookies), então o Postgres aplica as mesmas policies do sistema atual. O client
   `service_role` (ignora RLS) só aparece em adapters de `infrastructure`, chamado por casos de uso
   que **já validaram** autorização (fluxos públicos de placa por token, e-mail, filas, webhooks).

## Composition root

`shared/composition/server-container.ts` monta, por request, os casos de uso com seus adapters
concretos. As rotas/route handlers pedem casos de uso ao container — não instanciam adapters.
Isso centraliza o *wiring* e mantém a presentation ignorante de infraestrutura.

## Escalabilidade

- **Vertical slices por feature** → times/áreas evoluem módulos em paralelo sem colisão.
- **Núcleo puro testável** → regras críticas (máquina de estados de placa, normalização de níveis,
  permissões) cobertas por testes unitários sem subir banco.
- **Adapters isoláveis** → cache, fila e provedores externos trocáveis sem tocar a regra.
- **Route Handlers finos** → fácil mover trabalho pesado (transcrição) para workers/filas.

## Convenções

- Imports via alias `@/` (raiz de `web/`). Ex.: `@/shared/domain/auth`, `@/modules/placas/...`.
- Arquivos kebab-case; tipos/entidades em PascalCase; casos de uso como verbo (`advance-auditoria.ts`).
- `domain`/`application` proibidos de importar `next/*` ou `@supabase/*`.
- Texto de UI e regras de produto replicam 1:1 o legado (estados, condicionais, observações).
