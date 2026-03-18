#!/usr/bin/env bash
# <xbar.title>Claude Token Usage</xbar.title>
# <xbar.version>v2.0</xbar.version>
# <xbar.author>yanwen</xbar.author>
# <xbar.refreshTime>5m</xbar.refreshTime>
# <xbar.desc>Shows Claude 5-hour session usage with countdown to reset.</xbar.desc>

CACHE_DIR="$HOME/.cache/claude-usage"
CACHE_FILE="$CACHE_DIR/usage.json"
LOG_FILE="$CACHE_DIR/plugin.log"
CACHE_TTL=290   # ~5 min; fresh fetch each xbar cycle, but rapid re-runs use cache

mkdir -p "$CACHE_DIR"

# ── Logging ──────────────────────────────────────────────────
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG_FILE"; }

if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 1000 ]; then
  tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

log "INFO" "Plugin run started"

# ── Auth ─────────────────────────────────────────────────────
CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
if [ -z "$CREDS" ]; then
  echo "Claude: no auth"
  echo "---"
  echo "Not logged into Claude Code"
  log "WARN" "No credentials found in Keychain"
  exit 0
fi

TOKEN=$(echo "$CREDS" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])
except Exception as e:
    sys.stderr.write(str(e))
" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "Claude: no token"
  echo "---"
  echo "Could not parse OAuth token — try: claude logout && claude login"
  log "ERROR" "Failed to parse accessToken from credentials"
  exit 0
fi
unset CREDS

# ── Fetch with cache ──────────────────────────────────────────
FETCH_STATUS="live"
USE_CACHE=false

if [ -f "$CACHE_FILE" ]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE") ))
  # Skip cache if it contains an error response (e.g. stale 401 body)
  if [ "$cache_age" -lt "$CACHE_TTL" ] && ! grep -q '"error"' "$CACHE_FILE" 2>/dev/null; then
    USE_CACHE=true
    FETCH_STATUS="cached (${cache_age}s ago)"
    log "INFO" "Using cache (age: ${cache_age}s)"
  fi
fi

if [ "$USE_CACHE" = false ]; then
  HTTP_CODE=$(curl -s -o "$CACHE_FILE.tmp" -w "%{http_code}" --max-time 10 \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.0.31" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

  if [ "$HTTP_CODE" = "200" ]; then
    mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    log "INFO" "API call success (HTTP 200)"
  elif [ "$HTTP_CODE" = "429" ]; then
    rm -f "$CACHE_FILE.tmp"
    log "WARN" "Rate limited (429) — backing off, using stale cache"
    if [ ! -f "$CACHE_FILE" ]; then
      echo "Claude: rate limited"
      echo "---"
      echo "Rate limited (429) — no cached data available"
      echo "Refresh | refresh=true"
      exit 0
    fi
    FETCH_STATUS="RATE LIMITED — stale data"
  elif [ "$HTTP_CODE" = "401" ]; then
    rm -f "$CACHE_FILE.tmp"
    log "WARN" "Unauthorized (401) — token expired, re-login may be needed"
    # Don't use stale cache for auth errors; show actionable message
    echo "Claude: auth expired"
    echo "---"
    echo "Token expired (401)"
    echo "Run: claude logout && claude login | terminal=true bash=/bin/bash"
    log "INFO" "Exiting due to 401 — user action required"
    exit 0
  else
    rm -f "$CACHE_FILE.tmp"
    log "ERROR" "API error (HTTP $HTTP_CODE)"
    if [ ! -f "$CACHE_FILE" ]; then
      echo "Claude: API error"
      echo "---"
      echo "API error (HTTP $HTTP_CODE)"
      echo "Refresh | refresh=true"
      exit 0
    fi
    FETCH_STATUS="ERROR (HTTP $HTTP_CODE) — stale data"
  fi
fi

unset TOKEN
DATA=$(cat "$CACHE_FILE")

# ── Parse ─────────────────────────────────────────────────────
IFS='|' read -r FIVE_PCT FIVE_LEFT FIVE_RESET_AT RATE_SYMBOL WEEK_PCT WEEK_SYMBOL WEEK_DELTA < <(
  printf '%s' "$DATA" | python3 -c "
import sys, json
from datetime import datetime, timezone

d = json.load(sys.stdin)
fh = d.get('five_hour') or {}
wk = d.get('seven_day') or {}

def time_left(resets_at, utilization=None):
    if not resets_at:
        if utilization == 0:
            return 'idle', ''
        return 'N/A', ''
    reset_time = datetime.fromisoformat(resets_at.replace('Z', '+00:00'))
    local_str = reset_time.astimezone().strftime('%H:%M')
    diff = int((reset_time - datetime.now(timezone.utc)).total_seconds())
    if diff <= 0:
        return 'reset', local_str
    h, rem = divmod(diff, 3600)
    m = rem // 60
    return f'{h}h{m:02d}m', local_str

def rate_symbol_and_delta(resets_at, pct, window_secs):
    if not resets_at:
        return '=', 0
    reset_time = datetime.fromisoformat(resets_at.replace('Z', '+00:00'))
    secs_left = max(0, int((reset_time - datetime.now(timezone.utc)).total_seconds()))
    secs_elapsed = window_secs - secs_left
    expected_pct = (secs_elapsed / window_secs) * 100
    delta = round(pct - expected_pct)
    if delta > 5:
        symbol = '▲'
    elif delta < -5:
        symbol = '▼'
    else:
        symbol = '='
    return symbol, delta

five_pct = fh.get('utilization') or 0
five_left, five_at = time_left(fh.get('resets_at'), fh.get('utilization'))
five_symbol, _ = rate_symbol_and_delta(fh.get('resets_at'), five_pct, 5 * 3600)

week_pct = wk.get('utilization') or 0
week_symbol, week_delta = rate_symbol_and_delta(wk.get('resets_at'), week_pct, 7 * 24 * 3600)
week_delta_str = f'+{week_delta}%' if week_delta >= 0 else f'{week_delta}%'

print(f'{int(five_pct)}|{five_left}|{five_at}|{five_symbol}|{int(week_pct)}|{week_symbol}|{week_delta_str}')
"
)

log "INFO" "5h: ${FIVE_PCT}% used, resets in ${FIVE_LEFT} (at ${FIVE_RESET_AT}) | 7d: ${WEEK_PCT}% ${WEEK_SYMBOL} (${WEEK_DELTA} vs pace) | source: $FETCH_STATUS"

# ── Output ────────────────────────────────────────────────────
echo "Claude: ${FIVE_PCT}% (${FIVE_LEFT}) ${RATE_SYMBOL}"
echo "---"
echo "7-day: ${WEEK_PCT}% ${WEEK_SYMBOL} (${WEEK_DELTA} vs pace)"
echo "---"
echo "Source: ${FETCH_STATUS}"
echo "Last checked: $(date '+%H:%M:%S')"
echo "---"
echo "Refresh | refresh=true"
echo "Open log | bash='open' param1='$LOG_FILE' terminal=false"
