-- =====================================================================
-- Migração 0005: a chave anônima fora de tudo
--
-- O Supabase concede SELECT/INSERT/UPDATE/DELETE a anon em toda tabela
-- nova do schema public e deixa a proteção por conta da RLS. Aqui anon
-- não tem o que fazer: nada é lido antes do login e, depois dele, o papel
-- é authenticated. Segunda camada, para uma política descuidada no futuro
-- não bastar para expor o portfólio a quem nem entrou.
-- =====================================================================

revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from public, anon;
alter default privileges in schema public grant  execute on functions to authenticated;
