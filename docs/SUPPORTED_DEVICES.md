# Supported Devices

RazerMon includes battery-query mappings for the wireless keyboards and mice listed below. The catalog is based on OpenRazer device data and covers the USB product IDs of wireless, HyperSpeed, and receiver endpoints. Actual battery reporting can vary with firmware and receiver configuration.

Only 2.4 GHz USB receiver connections are supported. Bluetooth connections are not supported because macOS does not expose the 90-byte HID feature report the battery query needs over Bluetooth, and cable connections report a wired product ID that is not listed here. Wired-only devices are intentionally excluded.

## Keyboards

- BlackWidow V3 Pro (Wireless) (`1532:025C`)
- BlackWidow V3 Mini HyperSpeed (Wireless) (`1532:0271`)
- Pro Type Ultra (Wireless) (`1532:027B`)
- DeathStalker V2 Pro (Wireless) (`1532:0290`)
- DeathStalker V2 Pro TKL (Wireless) (`1532:0296`)
- BlackWidow V4 Mini HyperSpeed (Wireless) (`1532:02BA`)
- BlackWidow V4 Tenkeyless HyperSpeed (Wireless) (`1532:02D5`)

## Mice

- Mamba 2012 (Wireless) (`1532:0025`)
- Naga Epic Chroma (Wireless) (`1532:003F`)
- Mamba (Wireless) (`1532:0045`)
- Lancehead (Wireless) (`1532:005A`)
- Atheris (Receiver) (`1532:0062`)
- Lancehead Wireless (Receiver) (`1532:006F`)
- Mamba Wireless (Receiver) (`1532:0072`)
- Pro Click (Receiver) (`1532:0077`)
- Viper Ultimate (Wireless) (`1532:007B`)
- DeathAdder V2 Pro (Wireless) (`1532:007D`)
- Basilisk X HyperSpeed (`1532:0083`)
- Basilisk Ultimate (Receiver) (`1532:0088`)
- Naga Pro (Wireless) (`1532:0090`)
- Orochi V2 (Receiver) (`1532:0094`)
- Pro Click Mini (Receiver) (`1532:009A`)
- DeathAdder V2 X HyperSpeed (`1532:009C`)
- Viper Mini Signature Edition (Wireless) (`1532:009F`)
- Viper V2 Pro (Wireless) (`1532:00A6`)
- Naga V2 Pro (Wireless) (`1532:00A8`)
- Basilisk V3 Pro (Wireless) (`1532:00AB`)
- Cobra Pro (Wireless) (`1532:00B0`)
- HyperPolling Wireless Dongle (`1532:00B3`)
- Naga V2 HyperSpeed (Receiver) (`1532:00B4`)
- DeathAdder V3 Pro (Wireless) (`1532:00B7`)
- Viper V3 HyperSpeed (`1532:00B8`)
- Basilisk V3 X HyperSpeed (`1532:00B9`)
- DeathAdder V4 Pro (Wireless) (`1532:00BF`)
- Viper V3 Pro (Wireless) (`1532:00C1`)
- DeathAdder V3 Pro (Wireless) (`1532:00C3`)
- DeathAdder V3 HyperSpeed (Wireless) (`1532:00C5`)
- Pro Click V2 Vertical Edition (Wireless) (`1532:00C8`)
- Basilisk V3 Pro 35K (Wireless) (`1532:00CD`)
- Pro Click V2 (Wireless) (`1532:00D1`)
- Basilisk Mobile (Receiver) (`1532:00D4`)
- Basilisk V3 Pro 35K Phantom Green Edition (Wireless) (`1532:00D7`)

## Contributing Device Reports

If your wireless Razer keyboard or mouse is missing or does not report its battery level, open a GitHub issue with the product name, connection mode, and USB product ID. If the device is listed but shows no battery level, choose **Copy Diagnostics** from the RazerMon menu and paste the report into the issue; it omits serial numbers. Do not include serial numbers or other personally identifying device information.
