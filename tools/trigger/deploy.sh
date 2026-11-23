#!/bin/sh
set -eu
: "${CLOUDFLARE_API_TOKEN:?}" "${CLOUDFLARE_ACCOUNT_ID:?}"
dir=$(cd "$(dirname "$0")" && pwd)
api="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/edge-watch-trigger"
auth="Authorization: Bearer $CLOUDFLARE_API_TOKEN"
json="Content-Type: application/json"

curl -fsS -X PUT "$api" -H "$auth" \
	-F 'metadata={"main_module":"worker.js","compatibility_date":"2026-11-01","keep_bindings":["secret_text"],"observability":{"enabled":true}};type=application/json' \
	-F "worker.js=@$dir/worker.js;type=application/javascript+module" >/dev/null
if [ -n "${GITHUB_TOKEN:-}" ]; then
	jq -n --arg t "$GITHUB_TOKEN" '{name: "GITHUB_TOKEN", text: $t, type: "secret_text"}' |
		curl -fsS -X PUT "$api/secrets" -H "$auth" -H "$json" --data @- >/dev/null
fi
curl -fsS -X PUT "$api/schedules" -H "$auth" -H "$json" --data '[{"cron":"*/5 * * * *"}]' >/dev/null
curl -fsS -X POST "$api/subdomain" -H "$auth" -H "$json" --data '{"enabled":false}' >/dev/null
echo "edge-watch-trigger deployed"
