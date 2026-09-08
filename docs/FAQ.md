# Razer Battery Monitoring on macOS — FAQ

## How can I check a Razer mouse battery level on a Mac?

RazerMon displays the battery percentage of compatible wireless Razer mice in the macOS menu bar. Install the application in `/Applications`, launch it, and grant Input Monitoring permission when macOS requests access.

## Can I check a wireless Razer keyboard battery level on macOS?

Yes. RazerMon supports compatible battery-powered Razer keyboards connected through HyperSpeed or supported wireless receiver endpoints. See the [supported wireless Razer devices list](SUPPORTED_DEVICES.md) for the current catalog.

## Does RazerMon require Razer Synapse?

No. RazerMon communicates with compatible devices through macOS IOKit HID APIs and does not require Razer Synapse, a kernel extension, or a background driver.

## Does it support Razer HyperSpeed receivers?

RazerMon supports compatible HyperSpeed and dedicated USB receiver endpoints. It can identify paired products exposed by compatible receivers and display their battery levels separately.

## Does it support Bluetooth Razer devices?

Bluetooth endpoints present in the device catalog are recognized, but battery reporting depends on the device firmware and how macOS exposes that connection. Some models may only provide the required protocol through their USB receiver.

## Why does RazerMon need Input Monitoring permission?

macOS protects access to keyboard and mouse HID devices. Input Monitoring permission allows RazerMon to send read-only identity and battery queries to compatible hardware. RazerMon does not record keystrokes or pointer activity.

## Does RazerMon change mouse or keyboard settings?

No. It does not change lighting, DPI, polling rate, pairing, profiles, macros, or key bindings. It only queries device identity, paired-product information, and battery level.

## Will RazerMon drain my Mac or device battery?

RazerMon uses event-driven connection monitoring, per-device battery caching, tolerant low-frequency timers, and sleep-aware refresh behavior. It does not continuously poll every catalog entry and does not prevent display, idle, or lid-close sleep.

## Which macOS versions are supported?

RazerMon supports macOS 13 and later on Apple silicon and Intel Macs.

## What should I do if my device is missing?

Open a [GitHub device compatibility issue](https://github.com/ab4317/RazerMon/issues/new) with the product name, connection mode, and USB product ID. Do not include the device serial number or other personally identifying information.
