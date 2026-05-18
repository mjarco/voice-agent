#!/usr/bin/env bash
#
# seed-agenda.sh — seed personal-agent with test data for P040 manual
# verification (`docs/manual-tests/p040-agenda-notifications.md`).
#
# What this script does:
#   * Reads API_URL + API_TOKEN from .env.mobile (or env overrides).
#   * `--list`     (default): print today's agenda items + routine occurrences
#                  via GET /agenda. No mutations.
#   * `--seed-items`: POST /conversations/append three times, each with a
#                  voice-style utterance that the personal-agent's LLM
#                  extractor will turn into an `action_item` record for
#                  today. Prints the created record IDs.
#   * `--all`      shorthand for --list then --seed-items.
#
# What this script does NOT do:
#   * Create routines — routines require the approval flow (`/records/{id}/
#     approve-as-routine`). Create a routine once via the personal-agent web
#     UI and reuse it across test runs. Routines with `start_time` are what
#     T5/T11/T12 exercise; they're stable backend state, not per-run seed.
#   * Wait for LLM extraction to complete — that's synchronous in
#     `/conversations/append`'s response (`interpretation_status: succeeded`).
#     We surface failures but do not retry.
#
# Why exist:
#   The P040 manual test plan needs predictable backend state. Clicking
#   through the personal-agent web UI to create 3 action items every
#   verification run is slow + error-prone.

set -euo pipefail

# Show help before any env-checking so `--help` works on a fresh checkout.
case "${1:-}" in
  -h|--help)
    sed -n '2,30p' "$0"
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env.mobile"

# ─── Config loading ──────────────────────────────────────────────────────
# Precedence: shell env > .env.mobile. .env.mobile has lines like
#   API_URL=https://example.com/api/v1
#   API_TOKEN=...

if [[ -f "$ENV_FILE" ]]; then
  # Strip surrounding quotes if any. Skip lines that are comments / blank.
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    # If already set in env, keep that.
    if [[ -z "${!key:-}" ]]; then
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"
      export "$key=$value"
    fi
  done < <(grep -E '^[A-Z_]+=' "$ENV_FILE" || true)
fi

if [[ -z "${API_URL:-}" || -z "${API_TOKEN:-}" ]]; then
  echo "ERROR: API_URL and API_TOKEN must be set (via shell env or .env.mobile)." >&2
  echo "Got: API_URL=${API_URL:-<unset>}  API_TOKEN=${API_TOKEN:+<set>}" >&2
  exit 1
fi

# Normalize: strip trailing slash, ensure /api/v1 suffix is present.
API_URL="${API_URL%/}"
if [[ ! "$API_URL" =~ /api/v1$ ]]; then
  API_URL="$API_URL/api/v1"
fi

TODAY="$(date +%Y-%m-%d)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ─── Helpers ──────────────────────────────────────────────────────────────

curl_get() {
  curl --fail-with-body --show-error --silent \
    -H "Authorization: Bearer $API_TOKEN" \
    "$@"
}

curl_post() {
  curl --fail-with-body --show-error --silent \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    "$@"
}

list_agenda() {
  echo "→ GET /agenda?date=$TODAY&granularity=day"
  local response
  response="$(curl_get "$API_URL/agenda?date=$TODAY&granularity=day")"
  echo "$response" | python3 -c '
import json, sys
r = json.load(sys.stdin)
data = r.get("data", r)
items = data.get("items", [])
routines = data.get("routine_items", [])
print(f"\nAction items ({len(items)}):")
for it in items:
    print(f"  - [{it.get(\"status\")}] {it.get(\"text\")[:60]!r:60}  id={it.get(\"record_id\")}")
print(f"\nRoutine occurrences ({len(routines)}):")
for r2 in routines:
    occ = r2.get("occurrence_id")
    occ_label = f"occ={occ}" if occ else "occ=NONE"
    print(f"  - [{r2.get(\"status\")}] {r2.get(\"routine_name\")[:40]!r:40}  start_time={r2.get(\"start_time\") or \"--\"}  {occ_label}")
'
}

# Posts one voice-style utterance via /conversations/append. The
# personal-agent's LLM extractor converts the natural language into a
# knowledge record. We pick utterances phrased so the extractor reliably
# creates `action_item` records for today.
seed_one_item() {
  local utterance="$1"
  local idempotency="seed-$(date +%s)-$RANDOM"
  local session="p040-seed-$TODAY"

  local body
  body=$(python3 -c '
import json, sys
print(json.dumps({
  "session_id": sys.argv[1],
  "role": "user",
  "content": sys.argv[2],
  "content_type": "text/plain",
  "idempotency_key": sys.argv[3],
  "source": "p040-seed-script",
  "occurred_at": sys.argv[4],
}))' "$session" "$utterance" "$idempotency" "$NOW_ISO")

  echo "→ POST /conversations/append  utterance=\"$utterance\""
  local response
  response="$(curl_post -X POST -d "$body" "$API_URL/conversations/append")"
  echo "$response" | python3 -c '
import json, sys
r = json.load(sys.stdin)
print(f"  status={r.get(\"interpretation_status\")}  event_id={r.get(\"event_id\")}  conv={r.get(\"conversation_id\")}")
'
}

seed_items() {
  echo
  echo "Seeding 3 action items for today ($TODAY) via /conversations/append."
  echo "Each one is a single LLM round-trip; expect ~2-5 s per item."
  echo
  seed_one_item "Today I need to buy groceries"
  seed_one_item "Today I should call the dentist"
  seed_one_item "Today I have to finish the quarterly report"
  echo
  echo "Re-listing agenda to confirm new records landed:"
  list_agenda
}

# ─── Main ─────────────────────────────────────────────────────────────────

cmd="${1:---list}"
case "$cmd" in
  --list)
    list_agenda
    ;;
  --seed-items)
    seed_items
    ;;
  --all)
    list_agenda
    seed_items
    ;;
  -h|--help)
    sed -n '2,30p' "$0"
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo "Run with --help for usage." >&2
    exit 2
    ;;
esac
