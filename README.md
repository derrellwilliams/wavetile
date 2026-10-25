# Wavetile

A native iOS 26+ music player for Jellyfin

## Setup
```sh
brew install xcodegen
xcodegen generate        # re-run after adding/removing files in App/ or changing project.yml
open Wavetile.xcodeproj
```
`Wavetile.xcodeproj` is generated from `project.yml`. Edit the spec, not the project.

## Layout
| Path | What |
|---|---|
| `App/` | Thin app target (`@main`, assets) |
| `Packages/WavetileKit/Sources/JellyfinKit` | Server validation, Quick Connect, Keychain, library queries |
| `Packages/WavetileKit/Sources/DesignSystem` | Theme tokens, motion, components |
| `Packages/WavetileKit/Sources/PreviewSupport` | Fixtures for previews |
| `Packages/WavetileKit/Sources/Features` | Screens and view models |

## Iterating on design
- **Tokens:** `DesignSystem/Theme.swift` (colors, type, spacing, radii, artwork) and `DesignSystem/Motion.swift` (springs). Add a theme to `Theme.all` and it appears in Settings → Appearance.
- **Font:** Familjen Grotesk (SIL OFL) lives in `DesignSystem/Resources/Fonts`. It's registered at launch by `BrandFont.register()`, and the family name is set in `DesignSystem/Typography+Brand.swift`.
- **Icons:** Phosphor Bold, used through `Glyph` (`DesignSystem/Glyph.swift`). To add one, put its name in `scripts/fetch-icons.sh`, run the script, then add a `Glyph` case. Run `WEIGHT=fill scripts/fetch-icons.sh` to switch weights.
- **Drawer screenshots:** launch with `-openSettings` (Debug builds only) to start with the Settings drawer open.
- **Previews:** every component and screen has a `#Preview` backed by `Fixtures`, so no server is needed.
- **Hot reload:** install [InjectionNext](https://github.com/johnno1962/InjectionNext), launch it, run the Debug build in the Simulator, then save any Swift file. Screens using `@ObserveInjection` + `.enableInjection()` re-render in place.

## Tests
Unit and performance tests (queue logic, sync and downloads bookkeeping, search, and 50k-track query budgets):
```sh
cd Packages/WavetileKit
xcodebuild -scheme WavetileKit-Package -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

UI tests: an accessibility audit (`performAccessibilityAudit`) of Home, Library, an album, Now Playing and Settings, plus a launch-time metric. They need a signed-in session in the simulator:
```sh
xcodebuild -project Wavetile.xcodeproj -scheme Wavetile -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```
