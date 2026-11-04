#!/usr/bin/env bash
# =====================================================================
# Bateria de testes do banco.
#
#     bash supabase/testar.sh
#
# Sobe um Postgres próprio num diretório temporário, aplica as migrações
# (e a carga, se existir localmente) e roda os testes de SQL. Não toca em
# projeto nenhum do Supabase e não precisa de rede.
# =====================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGDIR="${PGDIR:-/tmp/pgprops}"
PORTA="${PORTA:-5598}"
USUARIO=props
BANCO=properties

cd "$RAIZ"
[ -x "$PGBIN/initdb" ] || { echo "erro: não achei o Postgres em $PGBIN (defina PGBIN)" >&2; exit 1; }

COMO=""
if [ "$(id -u)" = "0" ]; then COMO="su claude -c"; fi
rodar() { if [ -n "$COMO" ]; then su claude -c "$1"; else bash -c "$1"; fi; }

if ! "$PGBIN/pg_isready" -h "$PGDIR" -p "$PORTA" >/dev/null 2>&1; then
  echo "== subindo Postgres em $PGDIR =="
  rm -rf "$PGDIR"; mkdir -p "$PGDIR"
  [ -n "$COMO" ] && chown -R claude:claude "$PGDIR"
  rodar "$PGBIN/initdb -D $PGDIR/data -U $USUARIO --auth=trust -E UTF8 --locale=C" >/dev/null
  rodar "$PGBIN/pg_ctl -D $PGDIR/data -l $PGDIR/log.txt -o '-k $PGDIR -p $PORTA -c listen_addresses=' start" >/dev/null
  sleep 2
fi

psql_()       { rodar "PGOPTIONS='--client-min-messages=warning' $PGBIN/psql -h $PGDIR -p $PORTA -U $USUARIO -d $BANCO -v ON_ERROR_STOP=1 $*"; }
psql_teste()  { rodar "$PGBIN/psql -h $PGDIR -p $PORTA -U $USUARIO -d $BANCO -v ON_ERROR_STOP=1 $*"; }

echo "== banco limpo =="
rodar "$PGBIN/psql -h $PGDIR -p $PORTA -U $USUARIO -d postgres -q -c 'drop database if exists $BANCO' -c 'create database $BANCO'" >/dev/null

# Stubs do que o Supabase fornece e o Postgres puro não tem: papéis anon e
# authenticated com os privilégios padrão que o Supabase concede, o
# auth.jwt() lido de uma variável de sessão, e o schema storage.
cat > "$PGDIR/stubs.sql" <<'SQL'
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables    to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;
create schema if not exists auth;
create schema if not exists storage;
grant usage on schema auth, storage to anon, authenticated;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('teste.jwt', true), ''), '{}')::jsonb
$$;
create table storage.buckets (id text primary key, name text, public boolean default false, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id), name text, owner uuid
);
alter table storage.objects enable row level security;
grant all on storage.objects, storage.buckets to anon, authenticated;
SQL
[ -n "$COMO" ] && chown claude:claude "$PGDIR/stubs.sql"

echo "== migrações =="
psql_ "-q -f $PGDIR/stubs.sql" >/dev/null
for f in supabase/migrations/*.sql; do
  printf '   %s\n' "$(basename "$f")"
  psql_ "-q -f $RAIZ/$f" >/dev/null
done
if ls supabase/seed/*.sql >/dev/null 2>&1; then
  echo "== carga local (não vai para o Git) =="
  for f in supabase/seed/*.sql; do printf '   %s\n' "$(basename "$f")"; psql_ "-q -f $RAIZ/$f" >/dev/null; done
fi

# Testes versionados (sem números do portfólio) + testes da carga local, que
# ficam junto com a carga em supabase/seed/testes/ e não vão para o Git.
falhou=0
for t in supabase/testes/*.sql supabase/seed/testes/*.sql; do
  [ -f "$t" ] || continue
  echo; echo "== $(basename "$t") =="
  if ! psql_teste "-f $RAIZ/$t" 2>&1 | grep -aE "NOTICE|^-- |=====|ERROR" | sed 's/^psql:[^ ]*: //;s/^NOTICE:  /     /'; then
    falhou=1
  fi
done

echo
if [ "$falhou" = 1 ]; then echo "== FALHOU =="; exit 1; else echo "== tudo passou =="; fi
