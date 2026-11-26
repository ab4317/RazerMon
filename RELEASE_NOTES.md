# RazerMon 0.3.2

RazerMon 0.3.2 makes device detection more reliable, adds a diagnostics report for troubleshooting, and ships the release app with the App Sandbox enabled.

## Installation

Install the prebuilt app with Homebrew:

```sh
brew install --cask ab4317/tap/razermon
```

Alternatively, download `RazerMon-0.3.2-arm64.dmg`, open it, and drag RazerMon into Applications.

After updating, grant Input Monitoring permission again: RazerMon is ad-hoc signed, so its signature changes with each release and macOS treats the update as a new app.

## What's New

- The release app is now signed with its App Sandbox entitlements and the hardened runtime. Earlier releases were documented as sandboxed but shipped without the entitlements.
- A connected device whose battery cannot be read now stays in the menu as "Unavailable" instead of disappearing.
- Battery and serial requests check the device's reply status and retry when the receiver is not ready, which previously could show a wrong value or hide the device.
- Added **Copy Diagnostics** to the menu. It copies a plain-text report of the Razer HID interfaces and their raw replies for pasting into a GitHub issue. Serial numbers are not included.
- Added the Razer Pro Type Ultra 2.4 GHz dongle (1532:027B) as an unverified device.
- Removed the Razer Orochi V2 Bluetooth entry (1532:0095). Over Bluetooth, macOS does not expose the HID feature report the battery query needs, so its battery can never be read. The Orochi V2 remains supported through its USB receiver (1532:0094).
- Documented that only 2.4 GHz USB receiver connections are supported, and how to verify the app's sandbox entitlements.

## Requirements

- macOS 13 or later
- Apple silicon Mac
- Input Monitoring permission
- A 2.4 GHz USB receiver connection; Bluetooth and cable connections are not supported

RazerMon remains read-only and does not record keystrokes or mouse movement. The release app has only the App Sandbox and USB device entitlements and no network or file access; verify with `codesign -d --entitlements - /Applications/RazerMon.app`.
