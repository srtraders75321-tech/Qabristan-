#!/usr/bin/env bash
# Runs migrations and tests against a throwaway local PostgreSQL database.
# Needs a reachable PostgreSQL server. Override connection with PGHOST/PGUSER/PGPASSWORD/PGPORT.
# Usage: supabase/tests/run_local.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/../.."
db="kabristan_test_$$"
psql_admin=(psql -v ON_ERROR_STOP=1 -X -q -d postgres)
psql_db=(psql -v ON_ERROR_STOP=1 -X -q -d "$db")

cleanup() {
  # KEEP_DB=1 leaves the throwaway database in place so a surprising result can be inspected.
  if [ "${KEEP_DB:-0}" = "1" ]; then echo "KEEP_DB=1: database left in place: $db"; return; fi
  "${psql_admin[@]}" -c "drop database if exists \"$db\"" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${psql_admin[@]}" -c "create database \"$db\""

"${psql_db[@]}" -f "$here/_shim_supabase.sql"
for f in "$root"/supabase/migrations/*.sql; do
  echo "migration: $(basename "$f")"
  "${psql_db[@]}" -f "$f"
done
"${psql_db[@]}" -f "$root/supabase/seed/placeholder_permissions.sql"
"${psql_db[@]}" -f "$here/_helpers.sql"

for f in "$here"/*.test.sql; do
  [ -e "$f" ] || continue
  echo "test file: $(basename "$f")"
  "${psql_db[@]}" -o /dev/null -f "$f"
done

echo
"${psql_db[@]}" -At -F '|' -c "select case when ok then 'PASS' else 'FAIL' end, name, coalesce(detail,'') from t.results order by ctid" \
  | awk -F'|' '{ printf "%s  %s%s\n", $1, $2, ($3==""?"":"  -> "$3) }'

failed="$("${psql_db[@]}" -At -c "select count(*) from t.results where not ok")"
total="$("${psql_db[@]}" -At -c "select count(*) from t.results")"
echo
echo "$((total - failed))/$total passed"
[ "$failed" -eq 0 ]
