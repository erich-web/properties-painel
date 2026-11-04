# PRD — Monitor de Imóveis RPE Properties (painel web)

**Versão** 1.0 · nov/2026 · dono: CEO (Erich) · construção: equipe RPE App Factory

## Problema

O portfólio da RPE Properties (imóveis, terrenos, participações e aplicações) era acompanhado numa pasta de 3,5 GB no Mac, um Excel e um monitor estático
gerado pelo CFO virtual. O time operacional não tinha onde subir documento, atualizar contrato
de locação, ver pendência documental ou saber o que fazer na semana. O CEO não tinha, em um
lugar só, estoque disponível para locação, rentabilidade contra meta e recomendações de
compra/venda/reajuste.

## Usuários

- **CEO (admin):** visão executiva, recomendações, cadastro do time.
- **Operacional (2–4 pessoas):** documentos, contratos, tarefas, lançamentos de caixa, alertas.
- **Leitura:** sócios/consultores que só acompanham.

## Objetivos e métricas

| objetivo | métrica | meta |
|---|---|---|
| Acervo documental no painel, não no Mac | documentos-chave com arquivo no Storage | 100 % dos indexados em 30 dias |
| Pendência documental caindo | itens `pendente/vencido/falta` no checklist | −60 % em 90 dias |
| Contratos sob controle | contratos vencidos sem tarefa aberta | zero em 60 dias |
| Rentabilidade visível | imóveis com `status_meta = abaixo` com tarefa aberta | 100 % |
| Uso semanal | pessoas distintas logando por semana | ≥ 3 |

## Escopo do MVP (entregue)

1. **Visão geral:** 8 KPIs (valor de mercado, fundo gera renda, uso da família, NOI anualizado,
   yield vs meta 8 %, estoque, contratos vencidos, pendências), gráfico yield contratado × mercado
   por imóvel com a linha da meta, composição do patrimônio, estoque para locação, recomendações
   agrupadas (vender / alugar / decidir / regularizar / manter), tarefas da semana e alertas altos.
2. **Imóveis:** tabela filtrável (situação, meta, busca) e ficha completa (KPIs, recomendação,
   marcação com comparáveis, custos e dívidas, contratos, checklist, documentos, tarefas, alertas).
   Edição de dados, marcação e meta por imóvel.
3. **Contratos:** agenda de 90 dias (vencimentos e reajustes), tabela, criação/edição com link
   para o documento, exclusão (admin).
4. **Documentos:** mapa de pendências imóvel × item (clique muda o status), acervo com filtros,
   upload por arrastar, **importar da pasta** (sobe de uma vez os documentos-chave indexados),
   abrir com URL assinada.
5. **Tarefas:** kanban semana / andamento / backlog / concluídas; sugestões do CFO já no
   backlog com impacto anual; atribuição, prazo, prioridade.
6. **Caixa:** realizado mensal 2026 (tesouraria), NOI e yield realizados por imóvel, lançamento manual.
7. **Alertas:** lista com severidade, resolver ou transformar em tarefa.
8. **Equipe (admin):** cadastro de pessoas e papel; trilha de auditoria.

## Fora do escopo (por ora)

- OCR/leitura automática dos documentos subidos.
- Integração com a tesouraria (planilha) — a carga é feita pelo gerador local.
- Notificações por e-mail/WhatsApp de vencimentos.
- App nativo. O painel é mobile-first, mas web.

## Critérios de aceite (verificados)

- [x] Quem não está em `pessoas` não lê nem escreve nada (teste `0001_acesso.sql`).
- [x] `leitura` não escreve; `operacional` não mexe em pessoas/dívidas/mercado nem apaga.
- [x] KPIs do banco batem com o monitor v3.1 do CFO (teste de carga, fora do repositório).
- [x] Todas as páginas abrem no desktop e no celular sem erro de console (Playwright).
- [x] Upload e importação de pasta registram o documento e o caminho no Storage.
- [x] Chave anon é a única credencial no repositório; a carga real está fora do git.

## Riscos

- Link mágico pelo SMTP padrão do Supabase tem limite baixo de envios/hora — se o time crescer,
  configurar SMTP próprio.
- Arquivos acima de 50 MB não sobem no plano atual (ficam só indexados).
- Marcação a mercado é estimativa do CFO virtual com comparáveis públicos; não substitui laudo.
