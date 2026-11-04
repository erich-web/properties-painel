# Arquitetura

## Visão

```
navegador ──(https)──► GitHub Pages: index.html (estático, público)
    │
    └─ supabase-js ──► Supabase (sa-east-1)
                         ├─ Auth: link mágico (OTP por e-mail, fluxo implícito)
                         ├─ PostgREST: tabelas e views, RLS deny-by-default
                         ├─ RPC: registrar_acesso()
                         └─ Storage: bucket privado `documentos` (URL assinada 600 s)
```

Não há servidor próprio. O front é um arquivo; toda regra de negócio sensível e todo controle
de acesso estão no Postgres. A chave `anon` no HTML é pública por desenho — depois do
`0005_endurecimento.sql` ela não tem privilégio nenhum nas tabelas; só serve para iniciar o login.

## Dados (schema `public`)

| tabela | o que é | chave |
|---|---|---|
| `pessoas` | allowlist e papel (`admin`, `operacional`, `leitura`) | `email` |
| `imoveis` | ativo: tipo, situação, participação, custos, marcação (mín/base/máx), aluguel de mercado, recomendação, `meta_yield` (padrão 8 %) | `id` curto (VC, JG, …) |
| `contratos` | locação/temporada/comodato/intra-grupo: locatário, unidade, valor, início/fim, reajuste, status | uuid |
| `documentos` | acervo: categoria, validade, `caminho_storage` (null = só indexado na pasta), `caminho_original` | uuid |
| `checklist` | 8 itens por imóvel (matrícula, título, IPTU, certidão, seguro, receita, licenças, PJ) com status | (imovel, item) |
| `tarefas` | semana / andamento / backlog / concluída; `origem = cfo` são as sugestões do monitor | uuid |
| `movimentos` | caixa mensal por imóvel e tipo (receita/opex/capex/dívida/aporte), `intra_grupo` | uuid |
| `dividas` | financiamentos: saldo, parcela, fim | uuid |
| `alertas` | severidade, tema, prazo, estado | uuid |
| `mercado` | comparáveis e resumo da marcação (`mk_*`) | texto |
| `auditoria` | trilha de todas as escritas (gatilho) | uuid |

Views (SECURITY INVOKER, respeitam a RLS de quem chama):

- `v_imoveis_kpi` — por imóvel: custo total, valor na cota, receita contratada e realizada
  anualizada, NOI, `yield_contratado`, `yield_realizado`, `yield_mercado`, `gap_meta`,
  `status_meta` (`acima`, `abaixo`, `sem_renda`, `uso_proprio`, `fora_da_regua`), score documental,
  contratos vencidos, tarefas e alertas abertos. É a fonte de quase tudo que a tela mostra.
- `v_contratos_agenda` — dias para o fim, próximo reajuste, flag de vencido.
- `v_estoque` — imóveis disponíveis para locação.
- `v_caixa_mensal` — realizado por mês e tipo.

`meses_realizado()` conta os meses **fechados** com movimento nos últimos 12 para anualizar o realizado (×12/n); o mês corrente fica fora até fechar.

## Acesso

- `pessoa_atual()` casa `auth.jwt() ->> 'email'` com `pessoas` (SECURITY DEFINER, `search_path`
  fixo). `e_autorizado()`, `papel_atual()`, `e_admin()`, `pode_editar()` derivam dela.
- RLS (`0002_rls.sql`): `select` para autorizado em tudo; `insert/update` para `pode_editar`
  (admin + operacional) em contratos, documentos, checklist, tarefas, movimentos, alertas e
  `update` em imóveis; `delete` e qualquer escrita em pessoas, dívidas e mercado só admin;
  auditoria só admin lê.
- Storage (`0004_storage.sql`, ajustado em 0007): ler = autorizado; subir = `pode_editar`; sobrescrever e apagar = admin.
- `0005_endurecimento.sql`: revoga tudo de `anon` em tabelas, sequências e funções (e nos
  privilégios padrão), para que uma política descuidada no futuro não exponha nada a quem não
  entrou.
- `0006_advisors.sql`: `search_path` fixo nas funções de gatilho e `EXECUTE` revogado delas
  (gatilho não precisa). Ficam executáveis por `authenticated`, de propósito, as cinco funções
  que a RLS avalia e `registrar_acesso()`.
- `0007_auditoria_qa.sql`: gatilhos de proteção (`proteger_imovel`, `garantir_admin`,
  `carimbar_autor`, `criar_checklist`, `validar_movimento`), CHECKs numéricos, auditoria em
  dívidas e mercado, `authenticated` sem TRUNCATE/TRIGGER/REFERENCES, Storage com update só
  admin e bucket limitado (50 MB, PDF/imagens/Office).

## Front

- Estado em memória (`DB`), carregado de uma vez no login (`carregarTudo`) e recarregado por
  tabela depois de cada escrita (`recarregar`).
- Toda string do banco que vai para `innerHTML` passa por `esc()` (inclusive datas em texto livre); links externos só `http(s)` com `rel=noopener`. O teste de tela planta um payload de XSS na fixture e confere que não executa.
- Upload: caminho `<imovel|holding>/<categoria>/<prefixo>_<nome sanitizado>`; o importador de
  pasta casa `webkitRelativePath` com `documentos.caminho_original` e só sobe o que está indexado
  sem arquivo. Limite de 50 MB por arquivo (Storage).
- Visual: "dashboard SaaS azul" dos sistemas internos da RPE (sidebar, cards brancos, `blue-600`).

## Testes

- `supabase/testar.sh`: Postgres local, migrações, seed (se existir), `testes/*.sql`. Os testes
  simulam `anon`/`authenticated` com `set role` e o e-mail via setting `teste.jwt` (stub de
  `auth.jwt()`), cobrindo autorização por papel e consistência da carga.
- Tela: Playwright com um mock do `supabase-js` alimentado por fixtures do Postgres local
  (fora do repo), percorre todas as páginas, fichas, modais, mobile e o importador de pasta.
