#!/usr/bin/env bash
set -euo pipefail

# Supabase CLI emits shell-safe, quoted local credentials. Keep them in the
# process environment only; never copy these defaults to production.
eval "$(npx supabase status -o env)"
export NEXT_PUBLIC_SUPABASE_URL="${API_URL}"
export NEXT_PUBLIC_SUPABASE_ANON_KEY="${PUBLISHABLE_KEY:-${ANON_KEY}}"
export SUPABASE_SERVICE_ROLE_KEY="${SECRET_KEY:-${SERVICE_ROLE_KEY}}"
export DATABASE_URL="${DB_URL}"
export DIRECT_URL="${DB_URL}"
if [[ -z "${ENCRYPTION_KEY:-}" ]]; then
  export ENCRYPTION_KEY="$(printf '%s' "${SECRET_KEY:-${SERVICE_ROLE_KEY}}" | sha256sum | cut -d' ' -f1)"
fi
exec "$@"
