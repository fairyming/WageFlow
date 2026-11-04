# Repository Guidelines

## Project Structure & Module Organization

WageFlow is a native macOS menu-bar salary dashboard using SwiftUI and AppKit, with no third-party dependencies. Swift Package Manager requires Swift 5.9 or later; deployment targets macOS 13+.

- `Sources/WageFlow/`: application lifecycle, status item, dashboard, settings, and calendar picker.
- `Sources/SalaryCore/`: salary calculations, holiday models, synchronization, and local caching.
- `Tests/SalaryCoreTests/`: executable checks with synthetic fixtures.
- `scripts/build-app.sh`: app bundle generation and ad hoc signing.
- `.github/workflows/release.yml`: universal builds, CI artifacts, and tag-triggered releases.
- `resource/`: rendered interface previews referenced by README.
- `resource/AppIcon.png` and `resource/AppIcon.icns`: committed app icons; packaging copies the ICNS without regenerating it. Use `sh scripts/render-icon.sh` only when changing the icon design.
- `README.md`: setup, supported behavior, and calculation rules.

Keep calculation and synchronization logic outside views. Use WageFlow consistently for the application, executable, and user-facing branding.

## Build, Test, and Development Commands

Install Apple Command Line Tools, then run from the repository root:

- `swift run WageFlow`: launch the menu-bar app; keep the terminal process running.
- `swift build`: compile all targets for development.
- `swift run SalaryCoreChecks`: run the complete behavior checks.
- `sh scripts/build-app.sh`: build release binaries into `dist/WageFlow.app` and sign locally.
- `open dist/WageFlow.app`: launch the packaged app.
- `python3 scripts/render-previews.py`: regenerate PNG previews from native views with isolated demo data (macOS and Python 3 required).

## Coding Style & Naming Conventions

Use four-space indentation, `PascalCase` types, and `camelCase` functions and properties. Follow existing Swift conventions; no formatter or linter is configured. Keep AppKit and observable UI state on the main actor. Guard newer SwiftUI APIs with availability checks and retain macOS 13 fallbacks.

## Testing Guidelines

Checks use a custom executable with precondition assertions, not XCTest discovery; use `swift run SalaryCoreChecks`, not `swift test`. No coverage threshold is configured. Add behavior checks to the existing runner when extending core logic. Inject dates, time zones, network responses, and isolated defaults; tests must not require live holiday endpoints or personal salary records.

Cover lunch boundaries, rest days, adjusted working weekends, month/year changes, saved overrides, caching, and fallback failures. For interface changes, manually check first opening, reopening, long amounts, hidden income, themes, and Reduce Motion. Keep decorative animations layout-stable and time-driven; avoid animation state changes during initial layout.

## Calendar & Privacy Rules

Refresh holiday data monthly, preserve manual overrides, and retain GitHub → jsDelivr → Fastly fallback order. Uncached years immediately display estimated weekdays while fetching; retain that estimate on failure. Empty holiday arrays are unavailable data, not verified calendars. Keep salary settings local; never commit personal data or credentials.

## Commit & Pull Request Guidelines

No Git metadata is available here to establish historical conventions. Use focused imperative subjects, such as `Fix dashboard animation layout`. Describe behavior changes, link relevant issues, attach interface screenshots, and report validation and any unverified behavior. Update README when commands or calculation rules change.
