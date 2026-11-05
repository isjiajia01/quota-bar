# QuotaBar — Design System (skeleton v1, FROZEN)

A native SwiftUI `MenuBarExtra(.window)` panel showing how much quota is left across Magpie accounts.
It replaces the old Magpie flyout. Platform rules are in `docs/PLATFORM_CONSTRAINTS.md`, which wins on conflict.
Status: **frozen**. New tokens or components only through designer `extend`.

## Skeleton paths
- Tokens: `Sources/QuotaBar/Design/Tokens.swift` is the **only** file allowed to contain raw values.
- Components: `Sources/QuotaBar/Design/Components/*`. Template: `Design/QuotaPanel.swift`.
- View state: `Design/PanelState.swift`. Presentation (pure mapping and rules): `Design/Presentation.swift`.
- State pages: `Design/States/StatePages.swift`. Guards: `scripts/lint-tokens.sh` and `Tests/QuotaBarTests/*`.
- Run: `swift run QuotaBar --state-pages` shows every state in dark and light; add `--state=<name>` for one state.
  `swift run QuotaBar --fixture` runs the menu-bar app on the sample data. With no flag it uses the live
  `http://127.0.0.1:13425/v1/magpie/quotas`.
- Snapshots: `QUOTABAR_SNAPSHOT_DIR=<dir> swift test` writes PNGs. Use a scratch directory, never the repo.

## Tokens (Tokens.swift)
| Group | Values |
|---|---|
| Space | hair 1 · xxs 2 · xs 4 · s 8 · m 12 · l 16 |
| Radius | bar 2 · skeleton 3 · chip 4 · page 10 (state-page frame only) |
| Metric | panelWidth 360 · scrollCap 460 (panel ≈ 546 pt max) · ring 28 / stroke 3.5 · bar 44×4 · valueColumn 36 (min) · windowColumn 64 (wraps) · heroColumn 150 (max chip row) · rowHeight 22 (min) · iconButton 22 · dot 6 |
| TypeRole | title=headline · status=caption · provider=body semibold · heroValue=title3 semibold mono · meta=subheadline · row=callout · rowValue=callout medium mono · chip=caption mono · stateTitle · stateIcon=title2 |
| Palette | textPrimary/Secondary/Tertiary, track, chipFill, separator, skeleton (all semantic `NSColor`) · healthy=systemTeal · low=systemOrange · critical=systemRed · lowText light #935800 / dark #FF9F0A · criticalText light #C0222F / dark #FF6B60 |
| Motion | `disclosure` snappy 0.18 s · `value` easeOut 0.25 s. Both become nil under Reduce Motion. No continuous animation. |

The panel uses the inherited colour scheme and the system panel material. Dark is the reference look,
but nothing forces it. Level colours are fills. Level **text** uses the lowText/criticalText roles,
because system orange/red on a light panel measure about 3.5:1.

## Rules (on `window.remaining`, raw value preserved; only rendering clamps to 0…100)
- **Binding window** = the account window with the lowest `remaining`. Rows and gauges show it.
- **Levels:** healthy > 30 · low ≤ 30 (orange) · critical ≤ 10 (red).
- **Nearly empty = binding remaining ≤ 5.** Such accounts fold into a per-provider "N nearly empty · a–b%" row,
  which starts collapsed.
- **Hero ("Most left · <account>")** = the usable account with the highest binding remaining. This is a data fact,
  **not** a routing claim. We never say "recommended" or "current" (no routing contract). `last`/`lastServedAt` are ignored.
- **Percent label:** floor; "<1" for 0 < r < 1; "—" for unknown. Empty `windows` means *unknown*, never 0.
- **Ordering:** providers in first-appearance order. Inside a provider: hero → other usable accounts by remaining (desc) →
  nearly-empty group → problem accounts (error, no quota).
- **Stale data stays visible.** The header status becomes `Updated HH:mm · couldn't refresh` with a small amber glyph,
  and the tooltip carries the detail. There is no banner. Full-panel error appears only when there has never been data.
- **Emails are private.** Rows show only the local part, middle-truncated. The "Hide emails" toggle (⋯ menu,
  `@AppStorage("hideEmails")`) swaps it for "Account N", where N is the position within the provider in payload order.
  Any address or `{{EMAIL_*}}` inside error text **always** becomes "This account". Raw transport errors are never shown.
- **Old read:** if `readAt` is more than 30 min before now, a quiet clock glyph appears. Durations are recomputed from timestamps on every render.
- `until` is shown neutrally (hourglass + date). `resets.count` shows as a ↺N chip (reset credits, not the window reset).
  Window resets, `display` amounts and read age go in the row tooltip. There are no reset actions (the endpoint is read-only).

## View state (the only data input)
`PanelState = loading | empty(fetchedAt) | error(TransportIssue) | stale(PanelSnapshot, TransportIssue) | content(PanelSnapshot)`
plus `isRefreshing` and `hideEmails`. **Expanded** is local disclosure state (`initiallyExpanded: Set<providerID>`),
not a data state. Its state page is `StatePage.expanded`. Actions out: `PanelActions{refresh, openMagpie, setHideEmails, quit}`.
Per-account errors live inside `content`/`stale`. They are never transport failures.

| State page | Body | Header status |
|---|---|---|
| loading | 3 static skeleton rows (dashed rings) | Loading… |
| empty | tray icon, "No accounts yet", [Open Magpie] | Updated HH:mm |
| error | "Can't reach Magpie" + issue detail + [Retry] | Not connected |
| stale | full list (last good snapshot) | ⓘ Updated HH:mm · couldn't refresh |
| content | full list, groups collapsed | Updated HH:mm |
| expanded | full list, all nearly-empty groups open | Updated HH:mm |
| hiddenEmails | content with "Account N" labels | Updated HH:mm |

## Components (lookup order: component → template → primitive)
- **QuotaPanel** (template): header · hairline · body (`BoundedScroll`) · hairline · footer. Fixed 360 pt width.
- **PanelHeader**: "Quota left", `StatusLine`, ↻ (Refresh, or Retry when stale/error; dimmed while refreshing), ⋯ Menu (Hide emails, Quit ⌘Q).
- **StatusLine**: states as in the table above. "· refreshing…" is appended while refreshing.
- **ProviderSection** = **ProviderHeader** (ring · name · plan chip · "Most left · label" · hero % · ≤2 `WindowChip`s,
  the two lowest windows) + rows indented under the ring + **NearlyEmptyGroup** + problem rows. A single-account
  provider shows only the header (label instead of "Most left"). A single error/no-quota provider puts the note in the header.
- **AccountRow**: usable `label [badges] ▬bar %value window` · nearly-empty (same row, red value) ·
  error (⚠ label + 2-line note) · noQuota (tertiary "No quota reported"). The tooltip lists every window.
- **NearlyEmptyGroup**: ▸ chevron · red dot · "N nearly empty" · range. Expanded rows hang off a 1 pt guide, indented 12 pt.
- **AccountBadges**: plan chip (only when it differs from the provider plan) · ⌛ until · ↺N · clock (old read).
- Primitives: **QuotaRing** (dashed when unknown) · **UsageBar** · **Chip** (fixed size) · **WindowChip** · **RowOrStack** · **Hairline** · **IconButton** ·
  **StateMessage** · **LoadingPlaceholder** · **BoundedScroll** · **PanelFooter** ("Open Magpie ⌘⇧M").

## Text fitting (extend 2026-11-05)
Only **account identifiers** ellipsize (middle; full value is the first line of the row tooltip and the header `.help`).
Everything else stays whole:
- **Chips and numbers never truncate.** `Chip` is fixed-size; hero and row values are fixed-size (valueColumn is a minimum).
- **RowOrStack** (layout primitive): children sit in one row when all fit at ideal width (and ≤ `maxRow`), otherwise one per
  line. Provider name + plan chip → plan drops below; row label + badges → badges drop below; the two header window chips stack
  right-aligned when wider than heroColumn. The stat column is never compressed; the left column yields.
- **Wrap, don't cut:** provider names, header/row error notes (no line cap), status line and row window labels wrap.
- **Window abbreviation rule** (`Presenter.shortWindowName`, chips and rows): `" · "`→space · `N minutes/hours/days/weeks`→`Nm/Nh/Nd/Nw` ·
  drop a trailing `(…)` · drop a trailing `credits`/`tokens` after a qualifier (`Extra credits`→`Extra`; bare `Credits` stays).
  Tooltips show the full window name. Plan text only drops a leading provider name (`stripProvider`).
- Width 360 (was 340): +16 for the wrapping window column, +4 for labels. Review `stress-*.png` (synthetic long text).

## Height strategy
The body is a `ScrollView` sized to its measured content (`onGeometryChange`) and capped at `Metric.scrollCap`.
Header and footer stay fixed. The full fixture (22 accounts, 8 providers) is ≈910 pt uncapped, so it scrolls.
460 pt is an app choice, not an OS limit. Verify on the smallest display. Snapshot mode clips at the same cap,
because AppKit-backed ScrollView/Menu render as placeholders offscreen (`PanelRenderMode`).

## Negative rules
- No raw colours, hex, sizes, paddings, spacings, radii, font sizes, opacities or durations outside Tokens.swift
  (`scripts/lint-tokens.sh`, run by `TokenLintTests`).
- No new component or token outside designer `extend`. Keep this file and the snapshots in step.
- Views never decode JSON, fetch, log payloads, or show raw transport errors. No routing labels ("recommended", "current", "use").
- No loud error banners for stale data. No continuous or looping animation. No multicolour status-item art (template symbol only).
- Never commit snapshots made from live data. Never put real emails in fixtures, tests or snapshots.
