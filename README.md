# RazerMon

RazerMon is a read-only macOS menu bar utility that displays battery levels for devices connected through a Razer HyperSpeed multi-device receiver.

Current version: **0.1.0**

This is an independent, unofficial open-source project. It is not affiliated with or endorsed by Razer Inc. Razer and related product names are trademarks of their respective owners.

Supported hardware currently includes:

- Razer DeathAdder V3 Pro Wireless (`1532:00B7`)
- Razer DeathStalker V2 Pro Wireless (`1532:0290`)

RazerMon only sends device identity, paired-product, and battery-level queries. It does not modify lighting, DPI, pairing, profiles, or key bindings.

## Requirements

- macOS 13 or later
- Xcode with Swift 5.9 or later when building from source
- Input Monitoring permission

## Build and Install from Source

Clone this repository and open the project in Xcode:

```sh
open RazerMon.xcodeproj
```

Select the **RazerMon** scheme and **My Mac**, then press `Command-R` to build and run. The project uses local ad-hoc signing by default and does not contain a development team or certificate configuration.

To create a Release build from the command line:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project RazerMon.xcodeproj \
  -scheme RazerMon \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

The resulting application is located at `build/Build/Products/Release/RazerMon.app`. Install and launch it with:

```sh
ditto build/Build/Products/Release/RazerMon.app /Applications/RazerMon.app
open /Applications/RazerMon.app
```

On first launch, follow the in-app instructions to open **System Settings > Privacy & Security > Input Monitoring**, add RazerMon, and enable access. Install the application in `/Applications` before granting permission so its path and permission identity remain stable.

RazerMon appears only in the macOS menu bar and does not display a Dock icon. Open its menu to view devices and battery levels, refresh immediately, manage launch at login, or quit. It refreshes automatically every minute and whenever the menu opens.

The application uses App Sandbox with USB device access. After installing it in `/Applications`, use **Launch at Login** in the menu to control whether it starts when you sign in.

## Protocol Validation

Every response must have the expected 90-byte length and pass XOR checksum, transaction ID, command class, and command ID validation. Serial numbers are deduplicated so cached responses from other transactions are not reported as additional devices.

## License

[MIT](LICENSE)
