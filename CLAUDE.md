# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# RightKit / 右键助手

macOS Finder right-click assistant. Five built-in actions: open in terminal, open in editor,
new file, new folder, copy path, plus configurable Python/Shell actions. Menu-bar app (`LSUIElement`, non-sandboxed) plus a
sandboxed Finder Sync extension. Product rules live in `README.md` — read it before
changing setup, permissions or the settings window.

## Identity

| | |
|---|---|
| Bundle IDs | `com.rightkit.app` / `com.rightkit.app.FinderSync` / `com.rightkit.app.shared` |
| App Group | `SAXZHR4HFD.com.rightkit.app` (single constant: `Preferences.appGroupID`, must match both entitlements) |
| URL scheme | Built-ins: `rightkit://run?action=…&target=…&container=…`; scripts: `rightkit://custom?ticket=<UUID>`; preview: `rightkit://import?url=…&market=…&sha256=…`; subscribe: `rightkit://market?url=…` |
| Min macOS | 13.0 |
| Version | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` |
| Team | `SAXZHR4HFD` |
| Log subsystems | `com.rightkit.app` (app), `com.rightkit.app.FinderSync` (extension) |

## Commands

Requires full Xcode and XcodeGen (`brew install xcodegen`).

```bash
./Scripts/generate-project.sh                 # project.yml → RightKit.xcodeproj (gitignored)
cd Packages/RightKitShared && swift test      # domain layer, no Xcode needed
cd Packages/RightKitShared && swift test --filter ActionLinkTests                      # one suite
cd Packages/RightKitShared && swift test --filter ActionLinkTests/testRoundTripWithoutContainer  # one test
python3 Scripts/generate-icons.py             # Design/*.svg → both asset catalogues
./Scripts/install-local.sh                    # build → sign → /Applications → launch
./Scripts/sign-app.sh <app> [identity]        # sign a staged bundle inside-out
./Scripts/release.sh                          # Developer ID + notarize + staple → dist/RightKit-<ver>.dmg
LOCAL=1 ./Scripts/release.sh                  # Apple Development, no notarization → dist/*-dev.dmg
```

Script knobs (env vars): `IDENTITY` (signing identity; default = first Developer ID,
else Apple Development), `CONFIG` (default `Release`), `NOTARY_PROFILE` (default
`rightkit-notary`, a `notarytool store-credentials` profile), `TIMESTAMP=0` for
`sign-app.sh` to skip the secure timestamp.

Compile check without signing:

```bash
xcodebuild -project RightKit.xcodeproj -scheme RightKit -configuration Release \
  -derivedDataPath build/DerivedData build \
  CODE_SIGNING_ALLOWED=NO ENTITLEMENTS_REQUIRED=NO
```

Both configurations are expected to build with **zero warnings**. Keep it that way.

Debugging a live install:

```bash
log stream --predicate 'subsystem BEGINSWITH "com.rightkit"' --level info
pluginkit -mAvvv -p com.apple.FinderSync | grep -A2 rightkit   # Path must be /Applications/RightKit.app
```

**Never test the extension via ⌘R in Xcode.** A Finder extension run from DerivedData
(or a mounted DMG) registers against a path that later vanishes, and pluginkit keeps
serving the stale copy. Use `install-local.sh`, then tick the extension in System
Settings → General → Login Items & Extensions → Finder extensions. If the `pluginkit`
path points elsewhere, delete that copy, reinstall, and re-tick.

## Architecture

```
RightKit.app  (Apps/RightKit)          menu bar, setup, settings, runs handed-off actions
 └─ RightKitFinderSync.appex           builds the submenu; hands everything else off
RightKitShared (Packages/…)            MenuAction, ActionRunner, Preferences, heartbeat, Strings
```

**Flow.** `FinderSyncExtension.menu(for:)` reads `Preferences.enabledActions`, filters by
`MenuAction.isAvailable(in:)`, and returns **one** parent item with a submenu. A click
resolves the action by `tag`, then `ActionLink.handOff` opens `rightkit://run?…`;
`AppDelegate.application(_:open:)` parses it and calls `ActionRunner.run`. Copy-path is
the exception (`MenuAction.runsInExtension`) — it writes the pasteboard in the extension
and only falls back to the handoff on failure.

**Custom actions.** `CustomActionStore` writes one atomic, versioned JSON catalog in the
existing App Group. Finder caches only its `CustomMenuItem` projection and immutable icon
PNGs, filters every selected item, and resolves clicks using the same `tag` snapshot as
built-ins. Groups are nested within the one RightKit submenu. Finder writes a short-lived,
single-use request ticket; the host claims it atomically, reloads the saved action and
rechecks availability. Never accept script text, arbitrary action IDs or file paths from
a bare custom-action URL. Never run scripts or read their external files in the extension.

New actions start as an empty `CustomAction` in the configuration tab. Do not add
built-in demo scripts or a template picker. Keep the editor compact: usage details
belong in `Docs/CustomActions.md` or tooltips; show errors and changing state when needed.
The menu-bar menu exposes Settings and Quit; access custom actions and running tasks
through Settings → Custom Actions.
Marketplace and portable import are implemented. See `Docs/MarketIntegration.md` for
the workflow and local integration checks; `plan/README.md` records the original design.

**Market imports.** `MarketHTTPClient` validates same-origin requests, bounded response
sizes, SHA-256 hashes and paginated catalogs. `MarketService` loads one query page at a
time (20 items by default, with 50/100 options), binds cached pages and ETags to the exact
URL, and ignores stale query results. Search and filters run on the server; update-only
queries target at most 100 installed IDs before local version filtering and pagination.
Legacy static catalogs without pagination metadata retain bounded full-snapshot loading.
Direct links bind to a market only after verifying the catalog or release
metadata. Both Debug and Release support HTTP and HTTPS markets, including LAN
addresses. ATS permits HTTP in the host app; origin, redirect, size, and digest
validation still apply to every market request.
Larger, centered top-level tabs switch between My Actions and Action Market. Only My Actions uses a
split view: the action list on the left and the selected editor (or an empty pane) on
the right. The market fills the content width and keeps action details in a sheet.
The local action sidebar also paginates without discarding the active draft. Page-size
controls use compact menu pickers. The sidebar places New / Duplicate / Delete above
a single pagination row containing page size, position, and Previous / Next controls.
The window and view share a 960 × 650 minimum content size; restored frames are clamped
to that minimum. The icon row shows only the current image and the
icon-library button. Users choose from 64 categorized SF Symbols with localized names;
there are no symbol-name or local-image inputs. Preserve images from existing and
market-imported actions until the user chooses a replacement from the library.
There is no Recent Runs button; history remains inside Manual Test.
`rightkit://import` immediately opens the shared loading/preview sheet, with visible
failure and retry states. It never runs a script. Importing stages an editable
draft; saving is the existing explicit step that updates the Finder catalog.

Update identity is the canonical market URL plus the package ID. `ActionPackageUpdate`
performs a three-way merge against the last imported baseline, preserving local runtime
configuration and compatible secret references. Independent copies retain provenance
but set `tracksUpdates = false`. Legacy clipboard imports and direct imports do not acquire market identity
from a matching package ID alone. Export omits secret values and machine-specific paths.

One market URL is configured in the Market Settings sheet, separate from browsing.
Edited URLs are verified before replacing the current source and cached catalog.
In-flight responses from an old URL are ignored, and the latest configuration request
wins. Importing a different market's action does not replace an existing configuration.
Legacy multi-market settings keep the first valid source and back up the original file
as `sources.legacy.json`. Installed actions retain their original market identity.
The app has no clipboard import UI or clipboard monitoring; legacy clipboard provenance
remains decodable for previously saved actions. Appearance follows the system by default
and can be changed in Settings without changing Finder's appearance. Hosted windows
use native blue control tint, not a primary-text tint.

`ScriptRunner` is shared by Finder runs and manual draft tests. It uses argv, never shell
interpolation, and a new POSIX process group with drained, bounded stdout/stderr. Stop,
timeout, shell completion and app quit clean up ordinary children; deliberately detached
daemons are outside this contract. Python is local/selected, never downloaded automatically.
`PythonInterpreter` honors an explicit interpreter first, then `VIRTUAL_ENV`, then
the dedicated `~/.venvs/rightkit` environment, before PATH and developer-tool locations.
Keep the selected symlink path intact so Python loads that venv's dependencies.
Timeout covers the full batch; per-item mode stops on the first failure.

Secret values are omitted by `ScriptEnvironmentVariable.Codable`; the host stores them in
Keychain. Edited secrets get new IDs before committing the catalog so a failed save cannot
overwrite credentials referenced by the old catalog. Read secrets only when running an
action, not when browsing Finder or opening settings. Logs redact exact secret values and
are retained in memory for the 20 latest runs. See `Docs/CustomActions.md` for the contract.

**Why handoff.** The appex is sandboxed and can be suspended the moment a menu handler
returns. Anything touching files, TCC or LaunchServices must run in the host.

### Load-bearing platform facts

Do not "simplify" these away; each one was a bug once.

- **Terminals are opened via LaunchServices, never AppleScript.** Terminal.app
  (`public.directory`), iTerm2 (OSType `fold`) and Ghostty (`public.directory`) all
  declare a folder document type, so `NSWorkspace.open(folder, withApplicationAt:)`
  lands in the right directory. This is why the app needs **no Apple Events entitlement
  and no Automation permission** (and no `NSAppleEventsUsageDescription`). Adding a
  terminal means checking its `CFBundleDocumentTypes` for a folder type first.
- **Never let Xcode sign the build; sign the staged bundle afterwards.** Signing during
  the build requires a provisioning profile for the App Group entitlement, which
  requires an Apple account signed into Xcode — without one, both `CODE_SIGN_STYLE`
  values fail (`No Account for Team …` / `requires a provisioning profile`). Both build
  scripts therefore build with `CODE_SIGNING_ALLOWED=NO` and call
  `Scripts/sign-app.sh`, which needs nothing but the certificate. Order inside that
  script matters: framework → appex → app, since signing the outer app first is
  invalidated by anything re-signed inside it.
- **The signature must carry a TeamIdentifier.** ad-hoc (`-`) signing makes pluginkit
  refuse to register the extension; `sign-app.sh` fails loudly rather than producing a
  bundle whose menu never appears. (The team ID comes from the certificate's OU — the
  value in the identity's parentheses is the *user* ID, not the team.)
- **Shared containers use a macOS team-prefixed App Group.** These builds have no
  provisioning profile, so `Preferences.appGroupID` and both entitlement files use
  `<signing team ID>.com.rightkit.app`. A `group.` identifier requires registered
  membership; without it macOS can prompt to access "data from other apps" whenever
  shared settings are read. `sign-app.sh` verifies the signed groups against the actual
  certificate's team and checks that both targets agree. Changing signing teams also
  requires updating the group ID in all three places. See Apple's
  [App Groups entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups).
- **Reload Finder extension workers after a local update.** Quitting the main app
  leaves the old extension processes alive. `install-local.sh` also stops
  `RightKitFinderSync` so Finder loads the current build on the next right-click.
- **One parent `NSMenuItem` with a submenu.** A flat menu gets spliced into Finder's own
  context menu. If no action is available the extension returns an empty menu rather
  than an empty submenu.
- **Action resolution by `tag`.** Finder strips `representedObject`; the index maps into
  the `menuActions` snapshot taken while building the menu. The selection is re-read on
  click and the snapshot is only used if the fresh read is empty.
- **Monitored directories = `/` + home + every mounted volume**, refreshed on
  mount/unmount. `/` alone does not reach other filesystems.
- **`APPLICATION_EXTENSION_API_ONLY = NO` on RightKitShared.** `ActionLink.handOff`
  calls `NSWorkspace.open`, which extension-only API rules forbid; keeping the call in
  the framework is what makes it legal for the appex to trigger it.
- **RightKitShared is an XcodeGen framework target, not an SPM product.** XcodeGen + SPM
  makes the Xcode GUI report "Missing package product" after every regenerate
  (`generate-project.sh` also strips the empty package hooks XcodeGen emits).
  `Package.swift` exists only for `swift test`.
- **No SwiftUI `Settings`/`Window` scenes.** In an `LSUIElement` app they cannot be
  opened imperatively from AppKit, and reaching the Settings scene needs the private
  `showSettingsWindow:` selector that SwiftUI now objects to. All windows go through
  `HostedWindow` (`Support/HostedWindow.swift`), registered in `AppWindows`.
- **The status item's first position is seeded.** AppKit appends a status item with no
  remembered position at the far *left* of the third-party area, which is where Ice /
  Bartender keep their hidden (or always-hidden) section — so on those machines a fresh
  install shows no menu-bar icon at all. `StatusItemPlacement.seedIfNeeded()` (called
  from `RightKitApp.init`, before the scene builds) writes
  `NSStatusItem Preferred Position Item-0`; `Item-0` is the autosave name SwiftUI's
  `MenuBarExtra` uses. The 360-point seed places the icon farther left, with other apps.
  The old 20-point seed is migrated once; other saved positions and later user drags
  are preserved.

### Authorization model

- **Finder extension toggle** is the only required setup permission. Custom scripts
  may access protected resources when explicitly run; no access is pre-requested.
  `SetupStatus.extensionEnabled = FIFinderSyncController.isExtensionEnabled || heartbeat.isLive()`
  — two cheap signals, no `pluginkit` subprocess, no `.unknown` state. Either counts as
  on, so a stale API read cannot warn about something that demonstrably works.
- **Verification is real, not assumed.** The extension writes `loadedAt` / `lastMenuAt`
  into the App Group (`ExtensionCheckIn`); `heartbeat.didServeMenu` is what turns the
  last setup step green. It doubles as proof the App Group is genuinely shared — if it
  were not, nothing would ever arrive. `isLive` means a check-in within the last 5 min;
  `lastMenuAt` is written at most every 30 s. 「重新引导」calls `ExtensionCheckIn.reset`
  so the checklist re-verifies the running build.
- **Install location** is checked (`/Applications`, `~/Applications`, disk image,
  elsewhere) because a Finder extension registered from a DMG or DerivedData path is the
  most common "it stopped working" cause. The step is hidden when the location is fine.
- **Folder access (TCC) is never pre-requested.** macOS prompts at first real access,
  where the context is clearest. Denials come back as `RightKitError.accessDenied`
  (classified in `RightKitError.fromFileSystem`) and the notification routes to
  Privacy → Files and Folders.
- **No Accessibility, no Automation, no notification permission at launch.** Notification
  authorization is requested on the *first failure* only; if refused, `Notifier` beeps
  and logs instead.
- **No hard gate in setup.** The primary button always works; its title switches between
  「以后再说」and「开始使用」.

### Key types

Shared:
- `MenuAction` — one enum carrying id, titles, symbol, app icon and availability. Adding
  a built-in action = adding a case and following the compiler. There is no registry and no
  parallel ID table.
- `TerminalApp` / `EditorApp` (`LaunchApps.swift`) — supported apps, their bundle IDs
  and the "Auto" order. `resolve(_:)` falls back to Auto when the chosen app is gone.
  Adding an app = adding a case (terminals: see the LaunchServices fact above).
  `AppLauncher` is the only code that talks to LaunchServices.
- `ActionContext` — `targets` + `container` only; every directory (`workingDirectory`,
  `creationDirectory`) is derived, so the handoff URL is lossless.
- `ActionRunner.run(_:in:preferences:)` — synchronous and throwing. No "degraded" result
  type: with AppleScript gone, an action either works or throws.
- `Preferences` — App Group `UserDefaults`. Unset `enabledActions` means all; an
  explicitly empty list is honoured (RightKit simply leaves the Finder menu).
  `Preferences(suiteName: nil)` is the test seam.
- `ExtensionCheckIn` / `ExtensionHeartbeat` — the check-in described above.
- `RightKitError` — each case carries a `recovery` route, which is what makes failure
  notifications actionable.
- `Strings` — all copy, Chinese-primary with English fallback picked from
  `Locale.preferredLanguages`. No `.strings` files.

App:
- `SetupStatus` — single source of truth for setup state; 1s poll only while a window is
  open (`addWatcher`/`removeWatcher`, a counter so two windows do not fight), plus a
  refresh on `didBecomeActive`.
- `SettingsModel` — observable face of `Preferences` + installed-app snapshot.
- `Notifier` — failure notifications and their click routing. Nothing else reports.
- `CustomActionsModel` — drafts, catalog edits, Keychain references, samples, at most
  three concurrent tasks and the last 20 run records. Manual tests never auto-save.
- `AppWindows` — setup, settings and the resizable custom-actions `HostedWindow`s.
- `StatusItemPlacement` — initial menu-bar position and legacy seed migration (see above).

## Conventions

- Edit `project.yml`, then run `./Scripts/generate-project.sh`. Never hand-edit the
  `.xcodeproj`.
- Icons are generated from `Design/` — edit the SVGs and re-run the script, never touch
  the asset catalogues by hand. macOS image sets take 1× and 2× only (a 3× child fails
  `actool`).
- User-visible text goes in `Strings`, never inline in a view.
- New permission surfaces need a real justification: the product's selling point is that
  it asks for one toggle and nothing else.
- Keep `Preferences.appGroupID` in sync with both `.entitlements` files.
- `DEVELOPMENT_TEAM` in `project.yml` only matters for Xcode-GUI builds. The scripts
  build unsigned, so the team on a scripted build comes from the signing certificate —
  override with `IDENTITY="…" ./Scripts/install-local.sh`. There are deliberately no
  xcconfig files duplicating build settings.
- Do not commit `*.xcodeproj/`, `build/` or `dist/`.
