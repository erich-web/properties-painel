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

## 7. Receita intra-grupo conta na renda do imóvel, mas aparece separada
**Decisão:** o aluguel que uma empresa do grupo paga ao imóvel (ex.: restaurante na Via Campos)
entra em `receita_contratada` e no `yield_contratado` — é caixa real da Properties, com contrato.
A view expõe também `receita_terceiros_mensal` e `yield_terceiros` (sem intra-grupo) e a ficha
mostra os dois. Comodato não entra em nenhum. **Pendente de confirmação do CEO:** se a visão
oficial da meta de 8 % deve ser "terceiros" (consolidado do grupo) ou "do imóvel" (fundo).

## 8. Funções de gatilho sem EXECUTE para `authenticated`
**Decisão:** `0006_advisors.sql`. O Postgres não checa `EXECUTE` ao disparar gatilhos; revogar
fecha `/rest/v1/rpc/registrar_auditoria` sem quebrar nada (testado no harness).

## 9. Correções da auditoria de QA (0007)
**Decisão:** aplicar antes de publicar — `meses_realizado()` só com meses fechados; CHECKs de
valor/meta/competência; operacional não desativa imóvel nem muda participação; nunca sem admin;
autoria carimbada pelo servidor; checklist nasce com o imóvel; sobrescrever objeto no Storage
só admin; bucket com limite de 50 MB e tipos permitidos. No front: escape em todo texto que
vira HTML (XSS armazenado confirmado e fechado), checklist só vira OK quando o arquivo subiu.
**Ficam para depois:** SRI/CSP e Tailwind compilado (precisa de rede para gerar os hashes),
SMTP próprio + captcha no login, convenção única de cota para renda/dívida (K3).
