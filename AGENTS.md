# Repository Guidelines

## Project Structure & Module Organization

RightKit targets macOS 13+. `Apps/RightKit/` contains the SwiftUI menu-bar app, features, services, and window support. `Extensions/RightKitFinderSync/` builds Finder menus and hands most actions to the host. `Packages/RightKitShared/` contains `Sources/RightKitShared/` domain logic and `Tests/RightKitSharedTests/` XCTest suites; its package manifest supports CLI testing, while Xcode builds a framework. Asset catalogs live under each target's `Resources/`; icon sources live in `Design/`.

## Build, Test, and Development Commands

Install full Xcode and XcodeGen (`brew install xcodegen`); package tests require Swift 5.9+. Run from the repository root:

- `./Scripts/generate-project.sh` — generate `RightKit.xcodeproj` from `project.yml`.
- `swift test --package-path Packages/RightKitShared` — run domain tests.
- `./Scripts/install-local.sh` — build, sign, install into `/Applications`, and launch; requires a signing certificate.

After generation, compile without signing:

```sh
xcodebuild -project RightKit.xcodeproj -scheme RightKit -configuration Release \
  -derivedDataPath build/DerivedData build \
  CODE_SIGNING_ALLOWED=NO ENTITLEMENTS_REQUIRED=NO
```

Keep Debug and Release builds warning-free.

## Coding Style & Naming Conventions

Use four-space indentation, `UpperCamelCase` types/files, and `lowerCamelCase` members. Follow surrounding Swift formatting; no formatter or linter is configured. Put user-visible copy in shared `Strings.swift`. Edit `project.yml` and regenerate the project. Generate assets with `python3 Scripts/generate-icons.py` after editing `Design/`.

## Testing Guidelines

Name XCTest classes `<Type>Tests` and methods `test<Behavior>`. Add regression tests for changed domain behavior; no numeric coverage threshold is configured. Filter tests with `swift test --package-path Packages/RightKitShared --filter ActionLinkTests`. Keep preference tests serial because they share a defaults suite.

Verify Finder changes through `install-local.sh`, then enable the extension in System Settings. Avoid testing via Xcode's Run command or mounted DMGs, which can leave stale extension registrations.

## Commit & Pull Request Guidelines

History contains one descriptive release commit, `RightKit 1.0.0: rebuild as a one-permission Finder assistant`; use concise, action-oriented subjects. PRs should explain behavior changes, link relevant issues, list test/build results and manual Finder checks, and include screenshots for UI changes. Keep generated projects, `build/`, and `dist/` out of commits.

## Architecture & Configuration

Read `README.md` and `CLAUDE.md` before changing setup or permissions. Preserve LaunchServices-based app launching and keep `Preferences.appGroupID` synchronized with both entitlement files.
