# Wavetile

A native iOS 26+ music client for Jellyfin

<img width="3241" height="1488" alt="wavetile" src="https://github.com/user-attachments/assets/4cfb75fe-5376-4a5d-8e44-516eff4793bf" />


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

