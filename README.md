# MacRo

MacOS bootstrapper & fast flag editor for the Roblox Player and Roblox Studio.

Included is the flag `DFFlagDisableDPIScale: true`, which fixes the display scaling issue on MacOS that causes Roblox to render in your scaled resolution instead of your native resolution.

![MacRo main window](docs/images/main-window.png)
![MacRo menu bar](docs/images/menu-bar.png)

## Requirements

- MacOS 14 or newer

## Installing

From Release:
Download the latest `MacRo.dmg` from Releases and mount it.

Homebrew:
```bash
brew tap staplecruncher/macro
brew install --cask macro
xattr -dr com.apple.quarantine /Applications/MacRo.app
```