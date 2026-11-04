-- =====================================================================
-- Migração 0002: controle de acesso (RLS)
--
-- Tudo negado por padrão. Quem é quem vem do e-mail do token, cruzado
-- com pessoas. Papéis:
--   leitura      lê tudo; não muda nada
--   operacional  lê tudo; cria/edita contratos, documentos, checklist,
--                tarefas, movimentos e alertas; edita o cadastro do imóvel
--   admin        tudo acima + pessoas, dívidas, mercado e exclusões
-- =====================================================================

alter table pessoas    enable row level security;
alter table imoveis    enable row level security;
alter table contratos  enable row level security;
alter table documentos enable row level security;
alter table checklist  enable row level security;
alter table tarefas    enable row level security;
alter table movimentos enable row level security;
alter table dividas    enable row level security;
alter table alertas    enable row level security;
alter table mercado    enable row level security;
alter table auditoria  enable row level security;

-- Pessoas: todo autorizado vê a equipe (para atribuir tarefas); só admin mexe.
create policy pessoas_ler   on pessoas for select using (e_autorizado());
create policy pessoas_admin on pessoas for all    using (e_admin()) with check (e_admin());

-- Imóveis: leitura geral; operacional/admin editam; só admin inclui/exclui.
create policy imoveis_ler     on imoveis for select using (e_autorizado());
create policy imoveis_editar  on imoveis for update using (pode_editar()) with check (pode_editar());
create policy imoveis_incluir on imoveis for insert with check (e_admin());
create policy imoveis_excluir on imoveis for delete using (e_admin());

-- Contratos, documentos, checklist, tarefas, movimentos, alertas:
-- leitura geral; operacional/admin criam e editam; admin exclui.
create policy contratos_ler     on contratos for select using (e_autorizado());
create policy contratos_criar   on contratos for insert with check (pode_editar());
create policy contratos_editar  on contratos for update using (pode_editar()) with check (pode_editar());
create policy contratos_excluir on contratos for delete using (e_admin());

create policy documentos_ler     on documentos for select using (e_autorizado());
create policy documentos_criar   on documentos for insert with check (pode_editar());
create policy documentos_editar  on documentos for update using (pode_editar()) with check (pode_editar());
create policy documentos_excluir on documentos for delete using (e_admin());

create policy checklist_ler     on checklist for select using (e_autorizado());
create policy checklist_criar   on checklist for insert with check (pode_editar());
create policy checklist_editar  on checklist for update using (pode_editar()) with check (pode_editar());
create policy checklist_excluir on checklist for delete using (e_admin());

create policy tarefas_ler     on tarefas for select using (e_autorizado());
create policy tarefas_criar   on tarefas for insert with check (pode_editar());
create policy tarefas_editar  on tarefas for update using (pode_editar()) with check (pode_editar());
create policy tarefas_excluir on tarefas for delete using (e_admin());

create policy movimentos_ler     on movimentos for select using (e_autorizado());
create policy movimentos_criar   on movimentos for insert with check (pode_editar());
create policy movimentos_editar  on movimentos for update using (pode_editar()) with check (pode_editar());
create policy movimentos_excluir on movimentos for delete using (e_admin());

create policy alertas_ler     on alertas for select using (e_autorizado());
create policy alertas_criar   on alertas for insert with check (pode_editar());
create policy alertas_editar  on alertas for update using (pode_editar()) with check (pode_editar());
create policy alertas_excluir on alertas for delete using (e_admin());

-- Dívidas e mercado: leitura geral; só admin altera.
create policy dividas_ler   on dividas for select using (e_autorizado());
create policy dividas_admin on dividas for all    using (e_admin()) with check (e_admin());
create policy mercado_ler   on mercado for select using (e_autorizado());
create policy mercado_admin on mercado for all    using (e_admin()) with check (e_admin());

-- Auditoria: admin lê; ninguém escreve pelo cliente (só o gatilho, security definer).
create policy auditoria_ler on auditoria for select using (e_admin());
