# quota-bar
Native macOS menu-bar panel for Magpie quotas (replaces the old Magpie.app flyout).

- Stack: SwiftUI content in an app-owned `NSStatusItem` + `NSPanel` (`App/PanelController.swift`), Swift 6, macOS only. The panel's SwiftUI tree is built on open and released on close.
- Data: `GET https://llm.isjia.page/v1/magpie/quotas` -> `{data:[account...]}`. The gateway authenticates `Authorization: Bearer`, read from the login Keychain (service `magpie-quota`, account `quota-bar`). Sample: `fixtures/quotas.sample.json` (emails scrubbed).
- Open Magpie: the panel footer and a global ⌘⇧M hotkey (Carbon `RegisterEventHotKey`, no Accessibility permission) launch the Safari-saved web app `~/Applications/magpie.app` (falls back to `https://magpie.isjia.page/` in Safari, then the default browser). The URL lives in `Sources/QuotaBar/App/MagpieLink.swift`.
- Refresh: one app-level loop (`QuotaStore.startAutoRefresh`, cadence in `RefreshPolicy`): fetch at launch, then every 60 s while the panel is open and every 5 min while it is closed; opening the panel fetches at once when the last attempt is over 30 s old. Failures double the delay (max 15 min). Polling pauses while the Mac sleeps, the displays sleep or the session is switched out. ⟳/Retry fetch immediately. One attempt at a time (8 s timeout); a failed attempt keeps the last snapshot as the `stale` state.
- Token: store it once in the login Keychain — `security add-generic-password -U -s magpie-quota -a quota-bar -w '<token>'` (the bearer token from Magpie's API keys). `QUOTABAR_TOKEN` overrides it for dev runs only.
- Run: `swift run QuotaBar` (live) · `swift run QuotaBar --fixture` (sample) · `swift run QuotaBar --state-pages` (design gallery).
- Package: `scripts/package-app.sh` builds release and writes `build/QuotaBar.app` (ad-hoc signed, `LSUIElement`, ATS exception for `127.0.0.1` only). It installs nothing.
- Account fields: provider, name, kind, plan, user, windows[{name,used,remaining,resetsAt,holds?}], readAt, lastServedAt, last, error, until, resets, resetsUsed.
- Never log or commit real emails or gateway keys.
