# RPE Properties — Monitor de Imóveis (painel web)

Painel de gestão do portfólio imobiliário da RPE Properties: imóveis, marcação a mercado,
rentabilidade contra meta, contratos de locação, documentos (acervo + pendências),
tarefas da semana e backlog, caixa realizado e alertas. Uso interno do time operacional.

- **Front:** uma única página (`index.html`) servida pelo GitHub Pages. Sem build, sem framework:
  Tailwind (CDN), Chart.js, Feather e `supabase-js`.
- **Back:** projeto Supabase próprio (Postgres + Auth + Storage). Toda regra de acesso é RLS no banco.
- **Login:** link mágico por e-mail. Só entra quem está na tabela `pessoas` (allowlist).
- **Dados:** nada de número no repositório. A carga real (`supabase/seed/`) fica fora do git.

## Estrutura

```
index.html                   painel completo (HTML + CSS + JS)
supabase/migrations/         0001 fundação · 0002 RLS · 0003 views · 0004 storage · 0005 endurecimento · 0006 advisors
supabase/testes/             testes de acesso e de carga (SQL), rodam no harness local
supabase/testar.sh           sobe um Postgres local, aplica migrações + seed + testes
supabase/seed/               (gitignored) carga real e geradores: gerar_carga.py, gerar_documentos.py
docs/                        PRD, arquitetura, decisões e manual de operação
```

## Rodar os testes

```bash
bash supabase/testar.sh        # precisa de Postgres 16 local (PGBIN=/usr/lib/postgresql/16/bin)
```

Sem rede e sem tocar no projeto do Supabase. Termina em `== tudo passou ==`.

## Publicar

1. Repositório público `erich-web/properties-painel`, GitHub Pages em `main` / raiz.
2. No Supabase (Authentication → URL Configuration): Site URL e Redirect URL =
   `https://erich-web.github.io/properties-painel/`.
3. Migrações já aplicadas no projeto `properties-painel` (região `sa-east-1`). Para uma migração nova:
   aplicar pelo MCP/CLI do Supabase **depois** de passar no `testar.sh`.

Reverter = `git revert` + push (o Pages republica em ~1 min). O banco não é tocado por deploy do front.

## Papéis

| papel        | lê tudo | cria/edita contratos, docs, checklist, tarefas, caixa, alertas | edita imóveis | pessoas, dívidas, mercado, apagar |
|--------------|:-------:|:-------------------------------------------------------------:|:-------------:|:--------------------------------:|
| leitura      | ✓       |                                                               |               |                                  |
| operacional  | ✓       | ✓                                                             | ✓             |                                  |
| admin        | ✓       | ✓                                                             | ✓             | ✓                                |

Quem não está em `pessoas` vê a tela de "acesso não liberado" e o banco não devolve nada.

Mais em `docs/OPERACAO.md`.
