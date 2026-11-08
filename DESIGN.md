# QuotaBar — Design System (skeleton v2, FROZEN)

A native SwiftUI `MenuBarExtra(.window)` panel showing quota left across Magpie accounts (replaces the Magpie flyout).
Platform rules are in `docs/PLATFORM_CONSTRAINTS.md`, which wins on conflict. v2 (extend 2026-11-08): cards, hero meters, pace,
row 5h/7d window pair.
Status: **frozen**. New tokens or components only through designer `extend`.

## Skeleton paths
- Tokens: `Sources/QuotaBar/Design/Tokens.swift` is the **only** file allowed to contain raw values.
- Components: `Sources/QuotaBar/Design/Components/*`. Template: `Design/QuotaPanel.swift`.
- View state: `Design/PanelState.swift`. Presentation (pure mapping and rules): `Design/Presentation.swift`.
- State pages: `Design/States/StatePages.swift`. Guards: `scripts/lint-tokens.sh` and `Tests/QuotaBarTests/*`.
- Run: `swift run QuotaBar --state-pages` (every state, dark + light; `--state=<name>` for one). `--fixture` runs the
  menu-bar app on sample data; no flag uses the live `http://127.0.0.1:13425/v1/magpie/quotas`.
- Snapshots: `QUOTABAR_SNAPSHOT_DIR=<dir> swift test` writes PNGs. Use a scratch directory, never the repo.

## Tokens (Tokens.swift)
| Group | Values |
|---|---|
| Space | hair 1 · xxs 2 · xs 4 · s 8 · m 12 · l 16 |
| Radius | bar 3 · skeleton 3 · chip 4 · card 10 (continuous) · page 10 (state-page frame and panel backdrop clip) |
| Metric | panelWidth 392 · scrollCap 500 (panel ≈ 590 pt max) · bar 56×6 (hero meters flex) · paceTick 2 wide, 3 overhang · valueColumn 38 (min) · trailingColumn 80 (wraps) · meterLabelColumn 58 (wraps) · rowHeight 22 (min) · iconButton 24 · cardStroke 0.5 · dot 6 |
| TypeRole | title=headline · status=caption · provider=body semibold · heroValue=title rounded semibold mono (+ heroUnit title3 for "%") · meta=subheadline · row=callout · rowValue=callout rounded semibold mono · meterLabel=subheadline medium · detail=caption mono · chip=caption mono · stateTitle · stateIcon=title2 |
| Palette | "Spruce" (below). textPrimary=labelColor · textSecondary=opaque #2E3734 / #D2DCD8 (variable-backdrop contrast; see below) · textTertiary=×0.42 (**glyphs only, never text**) |
| Motion | `disclosure` snappy 0.18 s · `value` easeOut 0.25 s. Both become nil under Reduce Motion. No continuous animation. |

Inherited colour scheme on one behind-window panel material; providers sit on translucent **cards** (see Card surface). No added shadows.
**Palette "Spruce"** (colour pass 2026-11-08): one signature hue, spruce (desaturated blue-green), means healthy and tints
every neutral (ink `#1C3E3A` light / mist `#C4E6DF` dark at low alpha). Low = ochre, critical = muted crimson. Bars: tinted
track + same-hue gradient fill (deeper start → softer tip, only via `Palette.*Fill`). Every custom role is dynamic with light,
dark and **Increase Contrast** variants (solid fills, deeper inks, 45 % strokes). Level is never colour-only (number beside bar).

| Role | Light | Dark |
|---|---|---|
| fills healthy · low · critical (start→tip) | #388579→#5AA698 · #A66E1E→#CB9640 · #A63842→#C95E5F | #379285→#5CB6A7 · #A8762E→#DEAA56 · #AE474D→#E27A72 |
| solid healthy · low · critical (glyph, dot) | #2E7D72 · #B07826 · #B4454B | #58B4A5 · #D6A04C · #DC6E69 |
| lowText · criticalText | #4D3002 · #78202B | #F6CC84 · #FFB8AC |
| track · chipFill · separator · card solid · stroke top→bottom · paceTick | ink 9 · 6.5 · 11 % · #FBFDFC 74 % · ink 7→12 % · #162422 80 % | mist 10 · 6 · 9 % · #D8ECE7 5 % · #E6F6F2 13→5.5 % · #F1F6F4 88 % |
| cardGlassTint (no per-card material) | mist #F2F9F7 30 % | spruce ink #122C29 30 % |
| panelGlassTint (over one `.hudWindow` NSVisualEffectView) | white 38 % | black 50 % |

## Panel and card surface (owner-authorized behind-window pass, 2026-11-08)
- **PanelGlass** (App/): one active `.behindWindow` `NSVisualEffectView`, `.hudWindow` material, with one contrast tint.
  Background windows are sampled by WindowServer. No per-card material, custom blur, timer, animation or polling in production.
- **Cards** = `cardGlassTint` + top-to-centre `cardSheen` + 1 pt gradient `glassRim`. Existing per-card material was removed.
- **Window workaround:** runtime inspection on macOS 27.3 found `MenuBarExtraWindow` already clear/nonopaque, but the hosting
  root prepends three full-size `_NSGraphicsView`s (the middle one opaque). `PanelGlass` recognises only this exact prefix,
  makes it transparent (saving/restoring alpha), and leaves all content alone. Reconciles on attach/layout/key-window/appearance;
  notifications are removed on detach. No private selectors, KVC, swizzling or deletion, but private class names/structure remain
  OS-fragile. An unrecognised hierarchy retains its system backing and shows a solid fallback. Recheck after OS updates.
- **Accessibility fallback:** Reduce Transparency or Increase Contrast hides the effect and supplies an opaque
  `windowBackgroundColor` panel; cards use existing `cardFill`. The tint changes do not affect layout.
- **Native contrast evidence:** fixture MenuBarExtra over a separate synthetic white/black window, screenshots converted to sRGB.
  Dark over white / light over black: header primary 6.86 / 5.32, header secondary 5.73 / 5.10, card secondary 6.98 / 6.65,
  critical card text 5.92 / 5.58, chip text 4.58 / 7.97. Low text uses darker/lightened opaque ink for the stale header as well.
  These are measured fixtures, not an all-wallpaper guarantee. Re-measure material/tint changes; native compositor checks matter.
- **Snapshots:** standard state/expanded/stress/fallback snapshots check layout. `glass-backdrop-*` is an unblurred synthetic
  layer-composition stress image, not a rendering of the AppKit window material. Native captures prove the actual blur.
  `rows-*` covers the row window pair (both slots, a missing slot, a credit-only row). `BoundedScroll`'s `snapshotFull` mode is
  rigidly sized (`fixedSize(vertical:)`): without it the renderer's second layout pass squeezes the card stack and stacked row
  bars overlap. That is a snapshot-mode artefact; the live panel is never squeezed (ScrollView content keeps its ideal height).
- **Debug QA:** `--fixture` plus `QUOTABAR_FIXTURE_APPEARANCE=dark` overrides only this process's appearance;
  `QUOTABAR_GLASS_DIAGNOSTICS=<scratch path>` dumps geometry and backing suppression (no quota identities), debug builds only.

## Rules (on `window.remaining`, raw value preserved; only rendering clamps to 0…100)
- **Binding window** = the account window with the lowest `remaining`. It decides status, ordering and the folded group, and it
  is the single bar of a row without a 5h/7d window (see Row window pair). Gauges show it.
- **Levels:** healthy > 30 · low ≤ 30 (ochre) · critical ≤ 10 (crimson).
- **Nearly empty = binding remaining ≤ 5.** Such accounts fold into a per-provider "N nearly empty · a–b%" row (starts collapsed).
- **Hero ("Most left · <account>")** = the usable account with the highest binding remaining. This is a data fact,
  **not** a routing claim. We never say "recommended" or "current" (no routing contract). `last`/`lastServedAt` are ignored.
  Its binding remaining is the card's one dominant number. No pooled average (it competes with the hero and implies pooling).
- **Percent label:** floor; "<1" for 0 < r < 1; "—" for unknown. Empty `windows` means *unknown*, never 0.
- **Ordering:** providers in first-appearance order. Inside a provider: hero → other usable accounts by remaining (desc) →
  nearly-empty group → problem accounts (error, no quota).
- **Stale data stays visible.** The header status becomes `Updated HH:mm · couldn't refresh` in lowText with an ochre (`low`) glyph;
  the tooltip carries the detail. There is no banner. Full-panel error appears only when there has never been data.
- **Emails are private.** Rows show only the local part, middle-truncated. The "Hide emails" toggle (⋯ menu,
  `@AppStorage("hideEmails")`) swaps it for "Account N", where N is the position within the provider in payload order.
  Any address or `{{EMAIL_*}}` inside error text **always** becomes "This account". Raw transport errors are never shown.
- **Old read:** `readAt` > 30 min before now → clock glyph + "2h 54m ago". Durations are recomputed from timestamps every render.
- `until` is shown neutrally (hourglass + date). `resets.count` shows as a ↺N chip (reset credits, not the window reset).
  Hero meters print the window reset ("resets 1h 0m"); rows keep it in the tooltip. There are no reset actions (read-only endpoint).
- **Amounts:** `display` + `unit` → "7.56 / 250 credits used" (display is used/limit in every observed record). `runsOutAt`
  is shown as **credit expiry** ("expires 13 Nov"), never as a projection — the constraints separate expiry from reset.

## Row window pair (extend 2026-11-08; `Presenter.rowLines` in Presentation.swift, tested in `RowLinesTests`)
Owner feedback: a non-primary row showed only its tightest window while the hero showed both. Every account row now shows the
**5-hour window above the 7-day window** as two thin bars, each with its own even-pace tick, in roughly one row's height.
- **Slots come from the parsed window length** (`Presenter.slot`): 5 hours → `5h`, 7 days → `7d`. Labels never decide a slot, so
  qualified names ("Gemini · 5 hours") still slot. Credits, Month, model pools and any other length are not slotted.
- **One window per slot**: the tightest of that length (lowest `remaining`; payload order on ties, and a window with no
  `remaining` only wins when no candidate reports one). Two 5h pools therefore contribute one bar; the pool qualifier stays in the
  tooltip, which lists every window.
- **Percents**: both stay in the value column as compact monospaced numbers. Only the tighter line takes its level colour
  (`lowText` / `criticalText`); the other stays `textPrimary`. Numbers are always present, so level is never colour-only.
- **Missing slot** (the account reports only one of the two lengths, e.g. a 7d-only plan): the slot keeps its row position with a
  neutral `track` bar and an em dash, so bars, percents and labels line up down the card.
- **Neither slot**: the row keeps the single-line layout of its binding window and its abbreviated window name (unchanged).
- **Tiny labels**: the trailing column shows `5h` / `7d` (or the abbreviated window name for an unslotted row). Labels are the
  `detail` role; the full name, reset time, elapsed share and pace explanation are in the row tooltip. No reset text in rows.
- **Projection** ("may run out ~HH:mm") stays under the row for the tighter line only, from that window's own pace.
- **Consequence**: a third, unslotted window that is tighter than both slots (e.g. a model pool at 8 %) is no longer the row's
  bar. It stays in the tooltip, exactly as the hero card shows only its two lowest windows. The card's number and status still come
  from the binding window.

## Pace (extend 2026-11-08; `Pace` in Presentation.swift, tested in `PaceTests`)
- **Window length** parsed from the name: `N minute/hour/day/week(s)` anywhere ("Gemini · 7 days"). Else unknown ("Month", "Credits").
- **Even-pace tick** at `1 − elapsed` on the remaining bar, `elapsed = 1 − (resetsAt − now)/length`. No tick when the length or
  `resetsAt` is unknown or elapsed falls outside 0…1. Fill short of the tick = burning faster than the clock. Tooltip says so in words.
- **Projection** "⏲ may run out ~HH:mm" (or "~d MMM HH:mm" on another day), lowText + speedometer glyph, only when pace
  (used ÷ elapsed, measured at `readAt`, else now) > 1, elapsed ≥ 10 %, quota > 0, the projected time is in the future and lands
  ≥ 10 % of the window before the reset. Linear, factual, never advice; none at 0 %.

## View state (the only data input)
`PanelState = loading | empty(fetchedAt) | error(TransportIssue) | stale(PanelSnapshot, TransportIssue) | content(PanelSnapshot)`
plus `isRefreshing` and `hideEmails`. **Expanded** is local disclosure state (`initiallyExpanded: Set<providerID>`),
not a data state. Its state page is `StatePage.expanded`. Actions out: `PanelActions{refresh, openMagpie, setHideEmails, quit}`.
Per-account errors live inside `content`/`stale`. They are never transport failures.

| State page | Body | Header status |
|---|---|---|
| loading | 3 static skeleton cards | Loading… |
| empty | tray icon, "No accounts yet", [Open Magpie] | Updated HH:mm |
| error | "Can't reach Magpie" + issue detail + [Retry] | Not connected |
| stale | full list (last good snapshot) | ⓘ Updated HH:mm · couldn't refresh (lowText) |
| content | provider cards, groups collapsed | Updated HH:mm |
| expanded | full list, all nearly-empty groups open | Updated HH:mm |
| hiddenEmails | content with "Account N" labels | Updated HH:mm |

## Components (lookup order: component → template → primitive)
- **QuotaPanel** (template): header · hairline · body (`BoundedScroll` of provider cards, 8 pt apart, 12 pt inset) · hairline · footer. 392 pt.
- **PanelHeader**: "Quota left", `StatusLine` (table above; "· refreshing…" appended), ↻ (Refresh / Retry when stale or error;
  dimmed while refreshing), ⋯ Menu (Hide emails, Quit ⌘Q).
- **ProviderSection** = `Card` { **ProviderHeader** (name · plan chip / "Most left · label" + old-read badge │ **HeroValue**) ·
  ≤2 **WindowMeter**s (the hero's two lowest windows, payload order) · hairline · rows · **NearlyEmptyGroup** · problem rows }.
  A single-account provider shows only header + meters (label instead of "Most left"). A single error/no-quota provider puts the
  note (⚠ glyph for errors) under the name and "—" as its number.
- **WindowMeter**: `label │ flexible UsageBar + pace tick │ value │ resets …`, then fact lines (amount used · expires) and a
  **ProjectionNote**. Tooltip: full name, %, amount, reset date, elapsed %, projection, expiry (`WindowText.tooltip`).
- **AccountRow**: usable `label [badges] │ ▬5h bar+tick │ % │ 5h` over `▬7d bar+tick │ % │ 7d` (see Row window pair) ·
  nearly-empty (same, tighter value criticalText) · error (⚠ label + note) · noQuota ("No quota reported"). Tooltip lists every
  window via `WindowText.tooltip`.
- **Column grid**: value column + 80 pt trailing column line up across meters, rows and the nearly-empty range (one % track per card).
  A row fills the same columns as a meter, so stacked percents sit under the hero's percent and the slot labels under the resets.
- **NearlyEmptyGroup**: ▸ chevron · critical dot · "N nearly empty" · range in the value column (criticalText). Expanded rows hang off a 1 pt guide, indented 12 pt.
- **AccountBadges**: plan chip (only when it differs from the provider plan) · ⌛ until · ↺N · clock + age (old read).
- Primitives: **Card** · **HeroValue** ("47" + small "%", or "—") · **UsageBar** (remaining fill, optional pace tick, fixed or flexible) ·
  **ProjectionNote** · **Chip** (fixed size) · **RowOrStack** · **Hairline** · **IconButton** · **StateMessage** ·
  **LoadingPlaceholder** · **BoundedScroll** · **PanelFooter** ("Open Magpie ⌘⇧M"). `QuotaRing`/`WindowChip` were retired in v2.

## Text fitting (extend 2026-11-05)
Only **account identifiers** ellipsize (middle; full value in the row tooltip / header `.help`). Everything else stays whole.
- **Chips and numbers never truncate.** `Chip` is fixed-size; hero and row values are fixed-size (valueColumn is a minimum).
- **RowOrStack** (layout primitive): children sit in one row when all fit at ideal width (and ≤ `maxRow`), otherwise one per
  line. Provider name + plan chip → plan drops below; row label + badges → badges drop below. HeroValue is never compressed.
- **Wrap, don't cut:** provider names, error notes (no line cap), status line, meter labels, reset text and row window labels wrap.
- **Row slot labels** are the fixed `5h` / `7d` tokens and never wrap; an unslotted row keeps the abbreviated window name, which
  wraps in the same trailing column. Full window names are tooltip-only.
- **Window abbreviation rule** (`Presenter.shortWindowName`, meters and rows): `" · "`→space · `N minutes/hours/days/weeks`→`Nm/Nh/Nd/Nw` ·
  drop a trailing `(…)` · drop a trailing `credits`/`tokens` after a qualifier (`Extra credits`→`Extra`; bare `Credits` stays).
  Tooltips show the full window name. Plan text only drops a leading provider name (`stripProvider`).
- Width 392 (was 360): owner-requested breathing room for 12 pt card insets and the trailing reset column. The live menu's
  native ScrollView had expanded its document to 392 at x=-16 in a 360 pt panel, clipping the cards despite ProviderList padding.
  `BoundedScroll` now constrains its document to `Metric.panelWidth`; runtime confirms its container begins at x=0 and cards retain
  equal 12 pt insets. This addresses the menu's automatic scrolling layout, not the glass layer. Review `stress-*`, `expanded-*`
  and `pace-*` in both appearances; snapshots alone cannot catch the MenuBarExtra-specific expansion.

## Height strategy
The body is a `ScrollView` sized to its content (`onGeometryChange`), capped at `Metric.scrollCap` (500, an app choice): two
full cards plus the next header; panel ≈590 pt fits a 13" display (verify). The full fixture (≈1 450 pt) scrolls. Snapshot mode
clips at the same cap (AppKit ScrollView/Menu render as placeholders offscreen, `PanelRenderMode`).

## Negative rules
- No raw colours, hex, sizes, paddings, spacings, radii, font sizes, opacities or durations outside Tokens.swift
  (`scripts/lint-tokens.sh`, run by `TokenLintTests`).
- No new component or token outside designer `extend`. Keep this file and the snapshots in step.
- Views never decode JSON, fetch, log payloads, or show raw transport errors. No routing labels ("recommended", "current", "use").
- No loud error banners for stale data. No continuous or looping animation. No multicolour status-item art (template symbol only).
- Never commit snapshots made from live data. Never put real emails in fixtures, tests or snapshots.
