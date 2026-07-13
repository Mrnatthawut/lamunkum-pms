#!/usr/bin/env bash
set -euo pipefail
eval "$(npx supabase status -o env)"

email="owner@dormitory.local"
password="DormitoryLocal!2569"
payload=$(printf '{"email":"%s","password":"%s","email_confirm":true,"user_metadata":{"display_name":"เจ้าของหอพัก Local"}}' "$email" "$password")
response=$(curl --silent --show-error --request POST "${API_URL}/auth/v1/admin/users" \
  --header "apikey: ${SECRET_KEY:-${SERVICE_ROLE_KEY}}" \
  --header "Authorization: Bearer ${SECRET_KEY:-${SERVICE_ROLE_KEY}}" \
  --header "Content-Type: application/json" \
  --data "$payload")

if [[ "$response" == *'"id"'* || "$response" == *'already been registered'* ]]; then
  echo "Local owner is ready: ${email}"
  echo "Development-only password: ${password}"
else
  echo "Unable to create local owner" >&2
  exit 1
fi
