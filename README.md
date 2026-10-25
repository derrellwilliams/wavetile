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

<img width="862" height="1866" alt="IMG_2663" src="https://github.com/user-attachments/assets/6b0cf099-9926-4544-a729-6f24bd20ba43" />
<img width="862" height="1866" alt="IMG_2664" src="https://github.com/user-attachments/assets/54dbf848-e750-4543-bbb2-bab507a21282" />
<img width="862" height="1866" alt="IMG_2660" src="https://github.com/user-attachments/assets/920ce845-2748-441a-ada5-702c44283586" />

