# Wavetile

A native iOS 26+ music client for Jellyfin

<img width="3045" height="2048" alt="wavetile" src="https://github.com/user-attachments/assets/21befe57-d58d-4533-ba1b-9fe92bd7ae0a" />


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

