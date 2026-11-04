# Decisões (ADR curto)

## 1. Mesmo padrão do painel do Campos Hall
**Decisão:** uma página estática no GitHub Pages + Supabase próprio + link mágico.
**Por quê:** o CEO já opera assim no Campos Hall; zero servidor para manter; custo ≈ US$ 10/mês;
RLS no banco é a única camada de segurança que importa. **Trade-off:** sem SSR, tudo carrega no
login (hoje < 1 s para ~1.300 linhas); se o volume de movimentos crescer muito, paginar.

## 2. Chave anon no HTML público
**Decisão:** aceitar. **Mitigação:** `0005_endurecimento.sql` revoga todo privilégio do `anon`;
views SECURITY INVOKER; storage privado. A chave só inicia o login.

## 3. Allowlist em tabela, não em metadados do Auth
**Decisão:** `pessoas.email` é a fonte da verdade; papel vive lá. **Por quê:** o admin cadastra o
time pelo próprio painel, sem console do Supabase; desativar é um clique.

## 4. Meta de yield 8 % a.a. por imóvel
**Decisão:** `imoveis.meta_yield` com padrão 0,08 (NOI / valor de mercado na cota), editável.
Fixada pelo CEO em 04/11/2026.

## 5. Documentos-chave primeiro
**Decisão:** indexar só os documentos-chave (matrículas, títulos, IPTU 2026, certidões, apólices,
contratos, financiamentos, alvarás, societário) com `origem = pasta` e subir o conteúdo pelo
**Importar da pasta** no navegador. **Por quê:** o ambiente de construção não alcança o Storage
(rede restrita) e a pasta tem milhares de arquivos, a maioria comprovantes e orçamentos. Documentos
pessoais (CNH, RG, certidões civis, declarações) ficaram deliberadamente fora do índice.

## 6. Contrato "vigente por prazo indeterminado" ≠ vencido
**Decisão:** status `indeterminado`; a view só marca `vencido` quando `status = vigente` e
`fim < hoje`. **Por quê:** evita inflar "contratos vencidos".

## 7. Restaurante (Mercearia Campos) como intra-grupo
**Decisão:** a receita do restaurante é marcada `intra_grupo`, contrato `intra_grupo/indeterminado`.
Entra no realizado de VC, mas aparece separada; a receita contratada "de terceiros" não a inclui.

## 8. Funções de gatilho sem EXECUTE para `authenticated`
**Decisão:** `0006_advisors.sql`. O Postgres não checa `EXECUTE` ao disparar gatilhos; revogar
fecha `/rest/v1/rpc/registrar_auditoria` sem quebrar nada (testado no harness).
