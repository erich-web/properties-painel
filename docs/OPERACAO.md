# Manual de operação

## Entrar

1. Abra `https://erich-web.github.io/properties-painel/`.
2. Digite o e-mail e clique em **Enviar link**. O link chega por e-mail (olhe o spam na primeira vez).
3. Se aparecer "acesso não liberado", seu e-mail ainda não está cadastrado: peça ao admin.

A sessão fica salva no navegador; **Sair** no rodapé da barra lateral.

## Cadastrar o time (admin)

**Equipe → Nova pessoa**: nome, e-mail, papel.

- `leitura` só vê. `operacional` opera o dia a dia. `admin` também cadastra pessoas, edita dívidas
  e marcação de mercado e apaga registros.
- Desativar alguém = desmarcar **ativo** (a pessoa some da allowlist na hora).

## Rotina semanal sugerida

| quando | quem | o quê |
|---|---|---|
| segunda | operacional | **Tarefas** → mover o que vai ser feito do backlog para *semana*, atribuir, dar prazo |
| diário | operacional | **Alertas** → resolver ou transformar em tarefa; **Contratos** → agenda de 90 dias |
| ao receber documento | operacional | **Documentos → Subir** (ou arrastar na ficha do imóvel); marcar o item do checklist como OK |
| fechamento do mês | financeiro | **Caixa → Novo lançamento** (ou recarregar a tesouraria pelo gerador) |
| mensal | CEO | **Visão geral**: yield × meta, estoque, recomendações; promover sugestões do CFO |

## Documentos

- **Mapa de pendências**: cada célula é um item do checklist. Clique para mudar o status
  (`ok`, `pendente`, `vencido`, `falta`, `não se aplica`) e anotar uma observação.
- **Importar da pasta** (uma vez, ou quando a pasta do Mac ganhar documentos novos já indexados):
  clique, escolha a pasta **IMÓVEIS - GRUPO RPE** inteira, confira o resumo ("N documentos-chave
  encontrados") e clique em **Subir**. O painel sobe só os arquivos do índice que ainda não estão
  no acervo; o resto da pasta é ignorado e nada é apagado. Leva alguns minutos.
- **Subir documento**: escolhe imóvel, categoria, título, validade; arraste um ou vários
  arquivos (até 50 MB cada). Pode marcar o item do checklist como OK no mesmo passo.
- **Abrir**: ícone de download gera um link válido por 10 minutos.

## Contratos

- **Novo contrato** / clique na linha para editar. Campos que movem KPI: valor mensal, fim,
  próximo reajuste, status (`vigente`, `vencido`, `indeterminado`, `minuta`, `encerrado`), tipo
  (`comodato` e `intra_grupo` não entram na receita contratada do fundo).
- Vincule o PDF pelo campo **documento** (precisa estar no acervo).

## Imóveis

- Ficha: **Editar** muda situação, recomendação, custos, aluguel de mercado, marcação e a meta
  de yield do imóvel (padrão 8 % a.a.).
- `status_meta`: `acima`/`abaixo` compara yield contratado com a meta; `sem_renda` = disponível ou
  uso do grupo sem contrato; `uso_proprio` = patrimônio da família (fora da régua de yield);
  `fora_da_regua` = terreno, obra, participação ou aplicação.

## Caixa

- Realizado 2026 vem da planilha de tesouraria (carga). Lançamento manual para o que não está
  lá. `intra_grupo` marca receita entre empresas do grupo (aparece separada).
- NOI e yield realizado anualizam pelo número de meses com movimento.

## Publicar uma mudança no painel

1. Editar `index.html` (ou migração nova em `supabase/migrations/`).
2. `bash supabase/testar.sh` → `tudo passou`.
3. Commit + push na `main` → GitHub Pages republica em ~1 minuto.
4. Migração nova: aplicar no projeto Supabase (MCP ou CLI) **só com aprovação do CEO**.

**Rollback do front:** `git revert <commit>` + push. **Rollback de migração:** escrever a
migração inversa; nunca editar uma migração já aplicada.

## Custos e limites

- Supabase: plano pago do projeto (≈ US$ 10/mês) — Storage 100 GB, arquivo ≤ 50 MB.
- Link mágico usa o SMTP do Supabase (limite baixo por hora). Se o time crescer, configurar
  SMTP próprio em Authentication → SMTP.
- GitHub Pages: gratuito, repositório público (só o HTML; sem dados).

## Quando algo dá errado

| sintoma | causa provável | o que fazer |
|---|---|---|
| "acesso não liberado" | e-mail fora de `pessoas` ou inativo | admin cadastra/ativa |
| link não chega | limite do SMTP ou spam | esperar 1 h / configurar SMTP próprio |
| upload falha "row-level security" | papel `leitura` | pedir `operacional` ao admin |
| upload falha "payload too large" | arquivo > 50 MB | comprimir o PDF ou deixar só indexado |
| número estranho num KPI | contrato com status/tipo errado ou movimento duplicado | corrigir na origem; a view recalcula na hora |
