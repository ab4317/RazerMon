# Razer Battery Monitoring on macOS — FAQ

## How can I check a Razer mouse battery level on a Mac?

RazerMon displays the battery percentage of compatible wireless Razer mice in the macOS menu bar. Install the application in `/Applications`, launch it, and grant Input Monitoring permission when macOS requests access.

## Can I check a wireless Razer keyboard battery level on macOS?

Yes. RazerMon supports compatible battery-powered Razer keyboards connected through a HyperSpeed or other supported 2.4 GHz USB receiver. See the [supported wireless Razer devices list](SUPPORTED_DEVICES.md) for the current catalog.

## Does RazerMon require Razer Synapse?

No. RazerMon communicates with compatible devices through macOS IOKit HID APIs and does not require Razer Synapse, a kernel extension, or a background driver.

## Does it support Razer HyperSpeed receivers?

RazerMon supports compatible HyperSpeed and dedicated USB receiver endpoints. It can identify paired products exposed by compatible receivers and display their battery levels separately.

## Does it support Bluetooth Razer devices?

No. Over Bluetooth, macOS does not expose the 90-byte HID feature report that the Razer battery query uses, so the battery level cannot be read. Switch the device to 2.4 GHz mode and connect it through its USB receiver. Cable connections are not supported either.

## Why does macOS say it could not verify RazerMon?

RazerMon is not notarized by Apple, because notarization requires a paid Apple Developer Program membership. macOS shows this warning the first time you open any downloaded app that has not been notarized; it does not mean a problem was found. Click **Done**, open **System Settings > Privacy & Security**, and click **Open Anyway** next to the RazerMon message. On macOS 14 and earlier, Control-click RazerMon in Applications and choose **Open**. The source code is public, and you can check what the app is allowed to do as described under "Does RazerMon access the network or my files?".

## Why does RazerMon need Input Monitoring permission?

macOS protects access to keyboard and mouse HID devices and requires Input Monitoring permission before an app can open them. RazerMon uses this access only to send read-only identity and battery queries to compatible hardware. It does not record keystrokes or pointer activity.

## Why do I have to grant Input Monitoring again after an update?

RazerMon is ad-hoc signed rather than signed with a developer certificate, so each release has a new code signature and macOS treats the update as a different app. After updating, enable RazerMon in **System Settings > Privacy & Security > Input Monitoring** again. If the existing entry no longer works, remove it and add RazerMon again.

## Does RazerMon access the network or my files?

No. The release app runs in the App Sandbox with only the `com.apple.security.app-sandbox` and `com.apple.security.device.usb` entitlements. It has no network or file-access entitlement. You can verify this with `codesign -d --entitlements - /Applications/RazerMon.app`.

## Does RazerMon change mouse or keyboard settings?

No. It does not change lighting, DPI, polling rate, pairing, profiles, macros, or key bindings. It only queries device identity, paired-product information, and battery level.

## Will RazerMon drain my Mac or device battery?

RazerMon uses event-driven connection monitoring, per-device battery caching, tolerant low-frequency timers, and sleep-aware refresh behavior. It does not continuously poll every catalog entry and does not prevent display, idle, or lid-close sleep.

## Which macOS versions are supported?

RazerMon supports macOS 13 and later. The prebuilt DMG and Homebrew installation are for Apple silicon Macs; on an Intel Mac, build it from source.

## What does "Unavailable" mean?

The device's receiver is connected, but its battery level could not be read. Check that the device is switched on and in 2.4 GHz mode. If it stays unavailable, report it as described below.

## What should I do if my device is missing?

Open a [GitHub device compatibility issue](https://github.com/ab4317/RazerMon/issues/new) with the product name, connection mode, and USB product ID. If the device appears as unavailable, choose **Copy Diagnostics** from the RazerMon menu and paste the report into the issue; it omits serial numbers. Do not include the device serial number or other personally identifying information.
