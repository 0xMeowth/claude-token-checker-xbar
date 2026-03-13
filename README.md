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

- Current 5-hour session usage percentage
- Time remaining until the session resets
- A rate indicator (`▲` above expected pace, `▼` below, `=` on pace)

## Notes

- Only tested on macOS with xbar. SwiftBar should work but is untested.
- Credentials are read from the macOS Keychain (written there by `claude login`) — no API key setup required.
- Usage data is cached for ~5 minutes to avoid hammering the API on rapid re-runs.
