-- =====================================================================
-- Migração 0006: fechando os avisos do linter de segurança do Supabase
--
-- 1. carimbar_atualizado / carimbar_conclusao rodavam sem search_path
--    fixo (aviso 0011). Trigger function com search_path mutável é vetor
--    clássico de sequestro de nome de função; fixa em public.
-- 2. Funções de gatilho não precisam ser chamáveis por ninguém: o
--    Postgres não checa EXECUTE na hora de disparar o gatilho, só na
--    criação. Tirar o EXECUTE de authenticated fecha o endpoint
--    /rest/v1/rpc/registrar_auditoria etc. (aviso 0029).
--
-- Ficam executáveis por authenticated, de propósito, as funções que a
-- RLS avalia no papel de quem chama: pessoa_atual, e_autorizado,
-- papel_atual, e_admin, pode_editar — cada uma só devolve algo sobre o
-- próprio chamador. registrar_acesso é chamada pelo painel no login.
-- =====================================================================

alter function carimbar_atualizado() set search_path = public;
alter function carimbar_conclusao()  set search_path = public;

revoke execute on function registrar_auditoria() from public, anon, authenticated;
revoke execute on function carimbar_atualizado() from public, anon, authenticated;
revoke execute on function carimbar_conclusao()  from public, anon, authenticated;
