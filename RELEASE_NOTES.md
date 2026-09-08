# RazerMon 0.3.1

RazerMon 0.3.1 adds simple binary installation for Apple silicon Macs through Homebrew and a downloadable DMG.

## Installation

Install the prebuilt app with Homebrew:

```sh
brew install --cask ab4317/tap/razermon
```

Alternatively, download `RazerMon-0.3.1-arm64.dmg`, open it, and drag RazerMon into Applications.

## What's New

- Added an Apple silicon DMG with a standard drag-to-Applications installer window.
- Added a Homebrew Cask distributed through `ab4317/homebrew-tap`.
- Added a reproducible release packaging script.
- Updated installation documentation to recommend Homebrew.
- Prevented the menu bar icon from briefly appearing undersized during launch.

## Requirements

- macOS 13 or later
- Apple silicon Mac
- Input Monitoring permission

RazerMon remains read-only and does not record keystrokes or mouse movement.
