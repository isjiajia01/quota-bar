# Platform constraints — quota-bar

Pinned inspection: 2026-11-05; Xcode 27.1 (27A9275), installed MacOSX SDK, Swift 6.4 per parent environment. Target is macOS 27 on this Mac. This document constrains implementation; it is not a design specification.

## Evidence locations

All paths below are relative to `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/`:

- **UI**: `SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`: 2087–2125 (`MenuBarExtra`), 2130 onward (Text/Image convenience labels), 5952 (`WindowMenuBarExtraStyle`).
- **Core**: `SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`: 3062–3064 (glass availability), 7987 onward (Material), 21074–21122 (ImageRenderer).
- **AppKit headers**: `AppKit.framework/Headers/NSStatusItem.h`: 31 (expanded interface lifecycle), 54–64 (length/button), 70–72 (visibility); `NSImage.h`: 170–182 (template-image processing); `NSScreen.h`: 40 (`visibleFrame`); `NSRunningApplication.h`: 31–42 (activation policies).

These declarations verify API existence, not undocumented window behavior. Apple documentation fetches returned navigation content, so no behavioral claim below relies on those fetches.

## Scene, layout, focus

- `MenuBarExtra` and `.window` style are available since macOS 13. It is a **Scene**, with content supplied as SwiftUI views. SwiftUI layout is proposed-size driven: constrain the content's width and height and put overflowing rows inside a bounded `ScrollView`. An unconstrained expanding scroll region is not a reliable intrinsic panel size.
- There is **no public size, maximum-height, resize-handle, window-position, or presentation binding on MenuBarExtra itself** in UI:2092–2125. `isInserted` means the status item exists, not that its panel is open. Do not use it to track visibility or polling.
- No universal numerical maximum panel height is documented in the inspected interface. The available display area varies with screen, scaling, Dock and menu bar; `NSScreen.visibleFrame` supplies available geometry. Any fixed designer height is an application choice, not an OS limit. Verify fit on the actual display; do not promise user resizing or that WindowGroup sizing modifiers affect this scene.
- Treat this as a transient system-managed panel, not a persistent application window. Outside-click/Escape dismissal, keyboard focus, search-field first responder, opening while another app is active, and multiple-display positioning **require native run verification**; declarations do not establish their exact macOS 27 behavior. `dismiss` must likewise be verified before relying on it for this scene. Avoid private window-class probing.
- Set bundle `LSUIElement=true` for an agent app without a Dock icon. The accessory activation policy permits windows but omits Dock/menu-bar participation (AppKit activation-policy declaration); prohibited policy cannot present UI. Include an explicit Quit action because there may be no ordinary app menu. Hiding/removing the only status item can make the app inaccessible.

## Packaging and networking

- For this bounded local app, use a **SwiftPM executable plus a generated `.app` bundle**. SwiftPM builds the executable; a packaging script must supply `Contents/MacOS`, `Contents/Info.plist` (executable, identifier, package type, LSUIElement, deployment version), and required resource bundles. Launch the bundle with `open`, rather than treating `swift run` as proof of Dock-less behavior. No Xcode project is required. Xcode is still needed for the SDK. Distribution signing/notarization is separate and untested.
- Use `URLSession` for `http://127.0.0.1:13425/v1/magpie/quotas`. The SSH tunnel is an external dependency: the panel must handle connection refusal, timeout, HTTP failures and malformed JSON. No tunnel-management process belongs in the first UI skeleton.
- ATS is separate from sandboxing. Use the narrow local-network intent (`NSAppTransportSecurity/NSAllowsLocalNetworking=true`) if an exception is needed; do not add `NSAllowsArbitraryLoads` by default. **ATS treatment of this literal loopback address on the target bundle has not been empirically verified.** A successful curl request does not establish URLSession ATS behavior. Acceptance must fetch from the packaged application and diagnose an ATS failure before expanding exceptions.
- An unsandboxed local build needs no sandbox network entitlement. If App Sandbox is enabled, outgoing client requests need `com.apple.security.network.client=true`; the app does not listen, so it does not need network-server entitlement. Entitlement enforcement and any local-network privacy prompt are unverified here; test the actual chosen signed configuration. Do not invent a gateway key: loopback forwarding already returned HTTP 200 in parent diagnostics.

## State lifetime and performance

- Own networking and retained data at app/store lifetime, not only within the transient content's `.task`. A view-scoped task may be cancelled with view removal; hidden content is not a reliable clock or lifecycle contract. MenuBarExtra provides no explicit `isPresented` binding in this SDK.
- Keep SwiftUI-observed state on MainActor; perform asynchronous network waits without blocking it. Allow one refresh at a time, cancel superseded work, use timeouts and backoff, and retain last successful data separately from last-attempt failure. Do not turn a single account's error into a whole-transport failure.
- App Nap, sleep and timer coalescing mean background polling is best effort, never an exact schedule. Recompute age/reset countdowns from timestamps rather than decrementing counters. Avoid per-row networking/timers and continuous animation while hidden. Validate that closing/reopening does not multiply polling tasks.
- UI/store boundary: UI receives accounts, loading/refreshing state, transport error, last successful fetch time and per-account read times; it emits refresh and local disclosure/selection actions. Expose fixture states for initial loading, loaded, empty, stale-with-error and per-account-error. No view should decode raw JSON or manufacture an account-selection claim.

## Status item, materials and appearance

- Supported public label forms include Text and Image (UI:2130 onward); the label builder accepts a View but does not guarantee arbitrary view layouts render as a full SwiftUI canvas in the status bar. Start with image/short text and verify the native result. Dynamic text may change item width: AppKit's variable length follows content (NSStatusItem.h:54). Space is finite and visibility can be obscured by the application menu (70).
- Template images are monochrome glyph inputs processed by AppKit for appearance and selection (NSImage.h:170–182). They are not a reliable vehicle for multicolor quota diagrams. Check light/dark menu bars and selected state separately from panel appearance.
- `glassEffect` is present from macOS 26 (Core:3062); system Materials also exist (Core:7987). Availability is verified, exact backdrop appearance is not. Do not assume nested glass, material and a system panel background composite identically in previews and live windows.
- Use semantic colors and inherited color scheme; any explicit appearance override must be intentional. Test light/dark, Increase Contrast and Reduce Transparency. Glass/material cannot be validated against a flat offscreen render alone.

## Data constraints from fixtures/quotas.sample.json

- The fixture has **22 records / 8 provider IDs**: Claude 2, Codex 5, Antigravity 6, WorkBuddy AI 5, and ZCode, WorkBuddy, OpenCode Zen Free, OpenCode Go 1 each. Do not hard-code a two-provider dashboard or assume all rows fit without scrolling.
- `user`, `plan`, `readAt`, `lastServedAt`, `last`, `error`, `until`, `resets`, `resetsUsed` are optional in observed data. `kind` includes `subscription` and `plan`. No stable account ID is supplied; provider alone is not unique, user can be absent, and index-based identity is unstable across refresh. Stable identity remains a model decision; handle collisions without dropping rows.
- `windows` can be empty **with or without** error. Empty means unknown/no reported quota, not zero remaining. Counts range up to 15 per account. `used`/`remaining` are fractional percentages, not Ints. Window names are arbitrary; windows may include provider pools, model names, credits and tokens, rather than just 5h/7d.
- `resetsAt` is optional. Other optional window fields include `pool`, `display`, `amount`, `limit`, `unit`, `runsOutAt`, `runsOut`, `holds`, `holdsWhy`. Reset time and credit expiry are different concepts. Clamp only visual progress rendering, preserving raw values. Unknown JSON keys must not break decoding.
- Timestamps contain no fraction or 3–9 fractional digits; test both parsing paths. Account `readAt` can precede fetch time substantially: a successful HTTP response does not prove fresh upstream quota. `last`/`lastServedAt` do not establish the next routed account; do not label one “recommended/current” without a routing contract.
- `resets` is an object containing `count`, `until`, `each[{until,id}]`; `resetsUsed` is an event array with user/at/why/windows. These are not the quota-window reset timestamp. Avoid adding interactive reset actions: the supplied endpoint is read-only.
- Error strings and nested reset history may contain identities. Scrubbing top-level `user` alone is insufficient for future fixtures/logs. Render errors as text; never dump live payloads, account addresses or credentials to logs/snapshots intended for sharing.

## Verification boundaries

- ImageRenderer exists since macOS 13 and exposes MainActor content, proposedSize, scale, optional cgImage (Core:21074–21122). Use deterministic fixture data, fixed dimensions and explicit light/dark environments for content snapshots. A render can be nil; check the result.
- Offscreen snapshots do not prove status-bar placement, event handling, focus, dismissal, native material backdrop, or embedded AppKit-view fidelity. Live `screencapture` of the **target window/region only** can verify compositing, subject to Screen Recording permission and visibility; capture no unrelated desktop content. No live render was performed in this constraints pass.
- Implementation gate: build/package/open; verify Dock absence and Quit, status-item appearance, open/outside-click/Escape/reopen, scroll with all 22 fixture accounts, small-screen fit, packaged localhost fetch, offline retention, empty/errors, fractional dates/values, and one polling loop after repeated opens. These runtime checks remain outstanding.
