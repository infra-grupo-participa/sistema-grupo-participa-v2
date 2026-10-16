# Radar (sistema original) no banco do Grupo

> Pedido do Luis Fernando (16/10/2026), com o aval do Victor Hugo. Dois nomes, para não confundir:
> - **sistema original**: o Radar de radar.grupoparticipa.app.br (repositório SistemaWEB, `sistemas/radar/`). Continua
>   sendo o principal e passa a usar o banco completo daqui.
> - **sistema do Participa**: a área Marketing › Web deste repositório. Vai ler só os dados principais do Radar
>   (o que a equipe precisa ver), a definir depois da migração.
>
> A tentativa anterior de refazer o Radar aqui (schema `mkt_web`, guia `docs/web-guia-luiz.md`, 05/10/2026) fica como
> está: este caminho não mexe nela.

## 1. O que entrou (migration `20261016201957_radar_original_estrutura`)

Tudo o que é do Radar está em **dois schemas próprios** e leva o comentário **"Radar (sistema original)"**:

| Onde | O quê |
|---|---|
| `radar` | 57 tabelas (com as partições de cliques por mês e de gravações por dia) e as funções do Radar |
| `radar_crm` | 15 tabelas do CRM do Radar. No banco antigo o schema se chamava `crm`; aqui mudou de nome porque o Grupo já tem o `crm` do Comercial. **Não confundir os dois** |
| `public.radar_*` | 22 funções de entrada (API da tela, coletor do gravador, porta externa, split, SendFlow). A `crm_receber` do Radar virou `public.radar_crm_receber` |

Nada fora disso foi criado ou alterado. **Tudo fechado**: RLS ligada sem policy em todas as tabelas (inclusive
partições), nenhuma função executável por `public`, `anon` ou `authenticated`, nenhum grant de tabela, nenhum cron,
nenhum segredo no vault. Os schemas `radar` e `radar_crm` **não** estão no `pgrst.db_schemas` (a API não os vê).

## 2. As tabelas, por área

| Área | Tabelas | Para o sistema do Participa? (a decidir) |
|---|---|---|
| **Projetos e páginas** (o contrato de cada funil) | `radar.projetos`, `radar.paginas_mapa`, `radar.apelidos`, `radar.publicacoes`, `radar.captacao` | provável: lista de projetos e páginas |
| **Visitas** (o gravador) | `radar.sessoes`, `radar.visitantes`, `radar.visualizacoes`, `radar.cliques` (por mês), `radar.erros`, `radar.pacotes`, `radar.recusas`, `radar.falhas` | os números agregados, não a visita a visita |
| **Funil** | `radar.eventos_funil` | provável: funil por etapa |
| **Gravações de vídeo** | `radar.gravacoes` (por dia), `radar.guardadas`, `radar.gravacoes_guardadas`, `radar.gravacoes_excluidas` | não (pesado; fica no original) |
| **Velocidade** | `radar.velocidade_lab` | talvez: a nota por página |
| **Melhorias** (achados) | `radar.achados`, `radar.achados_dia`, `radar.achados_registros`, `radar.diarios` | talvez: as prioridades |
| **Testes e split** | `radar.testes`, `radar.split_entregas` | talvez: o resultado de cada teste |
| **Tráfego (Meta)** | `radar.meta_anuncios_dia`, `radar.meta_rodadas` | cuidado: o Tráfego do Participa já tem `mkt_trafego` |
| **CRM do Radar** | `radar_crm.pessoas`, `radar_crm.envios`, `radar_crm.reenvios`, `radar_crm.aberturas`, `radar_crm.exclusoes`, `radar_crm.exportacoes`, `radar_crm.leituras_porta`, `radar_crm.parametros`, `radar_crm.chaves_servidor` | cuidado: o Grupo já tem `pessoas` e o `crm` do Comercial; casar por e-mail, nunca duplicar |
| **Grupo do WhatsApp** (SendFlow) | `radar_crm.sendflow_campanhas`, `radar_crm.sendflow_grupos`, `radar_crm.sendflow_chaves`, `radar_crm.sendflow_log`, `radar_crm.grupo_eventos`, `radar_crm.grupo_cache` | provável: ingresso no grupo por funil |
| **ActiveCampaign** | `radar.active_catalogo` | não |
| **Acessos e equipe** | `radar.membros`, `radar.funcoes`, `radar.chaves`, `radar.chaves_uso`, `radar.chaves_ritmo`, `radar.redes_internas`, `radar.visitantes_internos` | não (o Participa tem o `acesso` próprio) |
| **Manutenção do Radar** | `radar.config`, `radar.integracoes`, `radar.integracoes_registro`, `radar.espaco_diario`, `radar.tempos_api`, `radar.migracoes`, `radar.feedback` | não |

## 3. Os dados

Copiados pela API da Supabase a partir de **uma foto** do banco antigo (16/10/2026 17:37), com
`SistemaWEB/sistemas/radar/migracao-participa/copia_dados.py`:
- as **gravações de vídeo não vieram** (decisão do Luis: recomeçam do zero aqui);
- o id de cada membro foi trocado pelo id do **mesmo e-mail** no `auth.users` do Grupo. O `marcos@advmais.com` não tem
  conta aqui e ficou de fora do `radar.membros`;
- os 3 gatilhos do CRM ficaram desligados durante a carga e voltaram no fim;
- o Radar original **continua gravando no banco antigo** até a virada: o que chegar depois da foto vem numa cópia
  da diferença, na hora da virada.

## 4. O que ainda NÃO foi feito (a virada)

Cada item é uma migration própria, com ensaio, no padrão do `docs/manual-banco-de-dados.md`:
1. **Funções que mexem no `auth` compartilhado.** O Radar cria usuário, troca senha, bloqueia conta (`banned_until`)
   e derruba sessão (`radar.acessos_*`, `public.radar_acessos`, `radar_minha_senha`, `radar_primeiro_acesso`). Aqui o
   `auth.users` é de ~7 sistemas: bloquear alguém no Radar o bloquearia em todos. Revisar antes de abrir.
2. **Robô do Meta e reenvio ao Active**: usam a extensão `http`, que este banco não tem. Viram `ops.cron_post`
   (ADR 0001) ou edge function.
3. **Rotinas** (12 crons do Radar) no padrão do ADR 0001, e os 2 segredos no vault.
4. **Grants**: só o que o gravador e a tela precisam (`public.radar_coletar` para anon etc.).
5. **Troca das chaves** no sistema original: gravador das páginas, interface, porta externa, servidores do CRM,
   porteiro do split, robôs.
6. **Cópia da diferença** (o que chegou depois da foto) e conferência.

## 5. Reversão

`infra/supabase/migrations/20261016201957_reversao.sql`: apaga os schemas `radar` e `radar_crm` e as 22 funções
`public.radar_*`, e tira o registro do histórico. Não toca em mais nada.
