#!/usr/bin/env bash
# Run the migration-path test and the self-hosted server's policy tests.
#
# Both run against the local docker stack. The suite ends in ROLLBACK, so it
# writes nothing; a failure raises, which aborts the transaction and exits
# non-zero.
#
# The central tier's equivalent lives in the `rift-central` repository, beside
# the schema it tests.
#
#   ./scripts/db_test.sh
set -euo pipefail

CONTAINER="${RIFT_PG_CONTAINER:-supabase-db}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

psql_main() { docker exec -i "$CONTAINER" psql -U postgres -q -v ON_ERROR_STOP=1 "$@"; }

echo "── migration path ──────────────────────────────────────────"
"$ROOT/scripts/migration_test.sh"

echo
echo "── self-hosted ─────────────────────────────────────────────"
psql_main -f - < "$ROOT/self_hosted_server_migrations/tests/policies_test.sql" 2>&1 |
  sed 's/psql:<stdin>:[0-9]*: //'
echo "   self-hosted: passed"
