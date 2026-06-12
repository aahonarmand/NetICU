# Contributing to NetICU

Thanks for your interest in contributing! NetICU is a small, focused macOS app and welcomes issues and pull requests.

## Building

1. Clone the repo and open `NetICU.xcodeproj` in **Xcode 16 or later**.
2. In the **Signing & Capabilities** tab of both the `NetICU` and `NetICUTests` targets, change the **Team** to your own Apple Developer team (the committed team ID belongs to the maintainer and will fail on your machine). "Personal Team" (free Apple ID) works fine for local development.
3. Select the **NetICU** scheme and press ⌘R.

The project uses filesystem-synchronized groups (Xcode 16+): any `.swift` file placed inside `NetICU/` (or `NetICUTests/`) is picked up automatically — no need to edit the project file.

## Running tests

Press **⌘U** in Xcode, or from the command line:

```bash
xcodebuild test -project NetICU.xcodeproj -scheme NetICU -destination 'platform=macOS'
```

Unit tests live in `NetICUTests/` and cover the statistics engine (`StatisticsCalculator`), the timing-breakdown diagnosis (`PingBreakdown`), and the TLS-bypass gating (`HostClassifier`). If your change touches scoring, statistics, or diagnosis logic, please add or update tests.

## Code style

- **All code comments must be in English.** The UI is English-only too; the bilingual content lives in the README.
- Swift 5, SwiftUI, no third-party dependencies — please keep it that way unless there's a strong reason.
- Minimum deployment target is **macOS 13**. Newer APIs must be guarded with `if #available`.
- UI strings go through `Localization.swift` (`loc.t("key")`), not hardcoded literals.
- UserDefaults keys go in the `DefaultsKey` enum in `Models.swift`, never as inline strings.

## Pull requests

- Keep PRs focused — one logical change per PR.
- CI must pass (build + tests run on every PR).
- For releases, the version lives in `AppInfo.swift` (`version`, `build`, `changelog`) and in the project's `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` — maintainers bump these.

## Reporting security issues

Please see [SECURITY.md](SECURITY.md) — don't open public issues for security-sensitive reports.
