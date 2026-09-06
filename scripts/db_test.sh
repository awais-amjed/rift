#!/usr/bin/env bash
# Run the migration-path test and both databases' policy tests.
#
# The self-hosted suite runs against the local docker stack. The central suite
# runs against a scratch database created in that same Postgres — not against
# the hosted project, which has real accounts on it. The scratch database gets a
# tiny `auth` shim (a users table and `auth.uid()` reading the JWT claim, which
# is what Supabase's own definition does) so the central migrations apply
# unchanged. Only the files that define reachable surface are applied — 004
# (scheduling), 005 (storage) and 006 (a drop) aren't what these tests are
# about, so the list is explicit rather than a glob.
#
# Both suites end in ROLLBACK, so neither writes anything. A failure raises,
# which aborts the transaction and exits non-zero.
#
#   ./scripts/db_test.sh
set -euo pipefail

CONTAINER="${RIFT_PG_CONTAINER:-supabase-db}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="rift_central_test"

psql_main() { docker exec -i "$CONTAINER" psql -U postgres -q -v ON_ERROR_STOP=1 "$@"; }
psql_scratch() { docker exec -i "$CONTAINER" psql -U postgres -q -v ON_ERROR_STOP=1 -d "$SCRATCH" "$@"; }

# Applying the migrations to an empty database means every `DROP ... IF EXISTS`
# announces itself. The tests speak through NOTICE, so silence the migrations
# rather than the tests.
psql_migrate() {
  docker exec -i -e PGOPTIONS='-c client_min_messages=warning' \
    "$CONTAINER" psql -U postgres -q -v ON_ERROR_STOP=1 -d "$SCRATCH" "$@"
}

echo "── migration path ──────────────────────────────────────────"
"$ROOT/scripts/migration_test.sh"

echo
echo "── self-hosted ─────────────────────────────────────────────"
psql_main -f - < "$ROOT/self_hosted_server_migrations/tests/policies_test.sql" 2>&1 |
  sed 's/psql:<stdin>:[0-9]*: //'
echo "   self-hosted: passed"


echo
echo "── central (scratch database) ──────────────────────────────"
psql_main -c "DROP DATABASE IF EXISTS $SCRATCH" >/dev/null
psql_main -c "CREATE DATABASE $SCRATCH" >/dev/null
trap 'docker exec -i "$CONTAINER" psql -U postgres -q -c "DROP DATABASE IF EXISTS $SCRATCH" >/dev/null 2>&1 || true' EXIT

psql_migrate <<'SQL' >/dev/null
-- The pieces of Supabase the central migrations lean on. `auth.uid()` is
-- copied from Supabase's definition: policies are only as correct as this is.
CREATE SCHEMA IF NOT EXISTS auth;
-- 009 installs pg_net here, and 010-012 name it in their search_path.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE IF NOT EXISTS auth.users (id UUID PRIMARY KEY);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID
  LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid
$$;
DO $$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT USAGE ON SCHEMA public, auth, extensions TO anon, authenticated;
-- 011 publishes a table to Realtime. The publication is Supabase's, not the
-- migrations', so the shim provides an empty one to add to.
DO $$ BEGIN CREATE PUBLICATION supabase_realtime;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
SQL

for f in 001_schema 002_security 003_api 007_public_servers 009_push 010_push_relays 011_notifications 012_friends 013_dm_conversations 014_friend_paging 016_handle_at_signup; do
  psql_migrate -f - < "$ROOT/central_server_migrations/$f.sql" >/dev/null
done

psql_scratch -f - < "$ROOT/central_server_migrations/tests/policies_test.sql" 2>&1 |
  sed 's/psql:<stdin>:[0-9]*: //'
echo "   central: passed"

