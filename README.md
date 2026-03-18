# claude-token-checker-xbar

An [xbar](https://xbarapp.com) / [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that displays your Claude Code 5-hour session token usage in the macOS menu bar, with a countdown to the next reset.

![macOS only](https://img.shields.io/badge/platform-macOS-lightgrey)

## Prerequisites

- macOS
- [xbar](https://xbarapp.com) or [SwiftBar](https://github.com/swiftbar/SwiftBar)
- [Claude Code](https://claude.ai/code) installed and logged in (`claude login`)
- Python 3 (ships with macOS)

## Installation

1. Copy (or symlink) `claude_tokens.5m.sh` into your xbar/SwiftBar plugins directory:

   ```bash
   # xbar default
   ln -s "$(pwd)/claude_tokens.5m.sh" "$HOME/Library/Application Support/xbar/plugins/claude_tokens.5m.sh"

   # SwiftBar — adjust path to your plugins folder
   ln -s "$(pwd)/claude_tokens.5m.sh" "$HOME/Library/Application Support/SwiftBar/Plugins/claude_tokens.5m.sh"
   ```

2. Make sure the script is executable:

   ```bash
   chmod +x claude_tokens.5m.sh
   ```

3. Refresh xbar/SwiftBar.

## What it shows

- **Menu bar:** 5-hour session usage %, time to reset, and rate indicator (`▲` above expected pace, `▼` below, `=` on pace)
- **Dropdown:** 7-day usage % with run-rate indicator and delta vs linear pace, data source, and last-checked time

## File naming

xbar and SwiftBar determine the refresh interval from the filename. The format is `<name>.<interval>.sh`, where the interval uses `s` (seconds), `m` (minutes), or `h` (hours). For example:
- `claude_tokens.5m.sh` — refresh every 5 minutes
- `claude_tokens.30s.sh` — refresh every 30 seconds

**Do not set the interval below 5 minutes.** The Anthropic usage API will rate-limit you (HTTP 429). The plugin has a 290-second cache to absorb rapid re-runs, but a short filename interval will quickly exhaust it and you'll start seeing stale data or `Claude: rate limited` in your menu bar.

## Error states

| Menu bar shows | Cause | Fix |
|---|---|---|
| `Claude: no auth` | No credentials found in Keychain | Run `claude login` |
| `Claude: no token` | Credentials exist but OAuth token couldn't be parsed | Run `claude logout && claude login` |
| `Claude: auth expired` | API returned 401 — token expired | Run `claude logout && claude login` |
| `Claude: rate limited` | API returned 429 and no cached data is available | Wait and refresh, or increase the filename interval |
| `Claude: API error` | Any other non-200 response and no cached data | Check `~/.cache/claude-usage/plugin.log` |

## Caching

The plugin caches the last successful API response at `~/.cache/claude-usage/usage.json` with a 290-second TTL (just under the 5-minute refresh interval).

**Why:** xbar re-runs the plugin script on every menu bar click and on each refresh cycle. Without a cache, each interaction would hit the API, increasing the chance of hitting rate limits. The cache means only one live API call is made per refresh cycle; rapid re-runs within the window use cached data.

**Behaviour on errors:**
- **429 (rate limited):** falls back to stale cache if one exists; shows `Claude: rate limited` only if there's no cache at all.
- **401 (auth expired):** intentionally ignores the cache — stale data would be misleading, and you need to re-login anyway.
- **Other errors:** falls back to stale cache if one exists.
- **Error responses in cache:** if the cached file itself contains an API error body, the cache is skipped and a fresh call is made.

A log is kept at `~/.cache/claude-usage/plugin.log` and is automatically trimmed to 500 lines once it exceeds 1000.

## API response shape

The plugin calls `GET https://api.anthropic.com/api/oauth/usage` (requires `anthropic-beta: oauth-2025-04-20` header). Sampled response:

```json
{
  "five_hour": {
    "utilization": 2.0,
    "resets_at": "2026-03-18T12:00:01.099270+00:00"
  },
  "seven_day": {
    "utilization": 0.0,
    "resets_at": "2026-03-25T07:00:01.099297+00:00"
  },
  "seven_day_oauth_apps": null,
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "seven_day_cowork": null,
  "iguana_necktie": null,
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": null,
    "used_credits": null,
    "utilization": null
  }
}
```

- `utilization` is a percentage (0–100).
- `resets_at` is an ISO 8601 timestamp with UTC offset.
- The `seven_day_*` and `iguana_necktie` fields appear to be per-model or per-app breakdowns; currently `null` in all observed responses.

## Notes

- Only tested on macOS with xbar. SwiftBar should work but is untested.
- Credentials are read from the macOS Keychain (written there by `claude login`) — no API key setup required.
