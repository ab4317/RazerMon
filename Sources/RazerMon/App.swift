import AppKit
import Foundation
import IOKit.hid
import ServiceManagement

@main
final class RazerMonApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var devices: [DeviceStatus] = []
    private var errorMessage: String?
    private var isRefreshing = false
    private var refreshTimer: Timer?
    private var permissionTimer: Timer?
    private var permissionGuide: PermissionGuideWindowController?
    private var permissionPromptIsShowing = false

    static func main() {
        let app = NSApplication.shared
        let delegate = RazerMonApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = RazerIcon.appImage
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = RazerIcon.makeStatusItemImage()
        statusItem.button?.toolTip = "RazerMon"
        // Device rows have no click action, but they are live/available data.
        // Disable AppKit's automatic action-based graying and control each row explicitly.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()

        if hasInputMonitoringPermission {
            refresh()
        } else {
            showPermissionPrompt()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshIfAllowed() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.permissionDidChange() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        permissionTimer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) { refreshIfAllowed() }
    @objc private func refreshFromMenu() { refreshIfAllowed() }
    @objc private func showPermissionFromMenu() { showPermissionPrompt() }
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            @unknown default:
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Unable to Change Launch at Login"
            alert.informativeText = "Move RazerMon.app to the Applications folder, then try again.\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
        rebuildMenu()
    }
    @objc private func exitApp() { NSApp.terminate(nil) }

    private var hasInputMonitoringPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func permissionDidChange() {
        guard hasInputMonitoringPermission else { return }
        permissionGuide?.showAuthorizedState()
        if devices.isEmpty && !isRefreshing { refresh() }
        rebuildMenu()
    }

    private func showPermissionPrompt() {
        guard !hasInputMonitoringPermission, !permissionPromptIsShowing else { return }
        permissionPromptIsShowing = true
        let alert = NSAlert()
        alert.messageText = "RazerMon Requires Input Monitoring Access"
        alert.informativeText = "RazerMon needs this permission to read battery levels from connected Razer devices. It does not record keystrokes or mouse movement."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        permissionPromptIsShowing = false
        if response == .alertFirstButtonReturn, !hasInputMonitoringPermission {
            showPermissionDragStrip()
        }
    }

    private func showPermissionDragStrip() {
        if permissionGuide == nil {
            let guide = PermissionGuideWindowController()
            guide.onBack = { [weak self, weak guide] in
                guide?.hide()
                self?.permissionGuide = nil
                self?.showPermissionPrompt()
            }
            permissionGuide = guide
        }
        permissionGuide?.openSettingsAndPresent()
    }

    private func refreshIfAllowed() {
        guard hasInputMonitoringPermission else { rebuildMenu(); return }
        refresh()
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        rebuildMenu()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try RazerMonitor.readDevices() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .success(let devices): self.devices = devices; self.errorMessage = nil
                case .failure(let error): self.devices = []; self.errorMessage = String(describing: error)
                }
                self.rebuildMenu()
            }
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        if !hasInputMonitoringPermission {
            addDisabled("Input Monitoring permission required")
            let permission = NSMenuItem(title: "Enable Input Monitoring…", action: #selector(showPermissionFromMenu), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        } else if devices.isEmpty {
            addDisabled(isRefreshing ? "Reading devices…" : (errorMessage ?? "No connected Razer devices"))
        } else {
            for device in devices {
                let item = NSMenuItem(title: "\(device.name), \(device.batteryPercent)%", action: nil, keyEquivalent: "")
                item.view = DeviceMenuItemView(device: device)
                item.toolTip = "Serial: \(device.serialNumber)"
                // A disabled NSMenuItem is always shown in gray. These entries
                // are informational, but the connected devices are healthy.
                item.isEnabled = true
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = hasInputMonitoringPermission && !isRefreshing
        menu.addItem(refresh)
        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.isEnabled = true
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval {
            launchAtLogin.toolTip = "Approval is required in System Settings under Login Items"
        }
        menu.addItem(launchAtLogin)
        menu.addItem(.separator())
        let exit = NSMenuItem(title: "Exit", action: #selector(exitApp), keyEquivalent: "q")
        exit.target = self
        menu.addItem(exit)
    }

    private func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

}

private final class DeviceMenuItemView: NSView {
    private static let rowSize = NSSize(width: 330, height: 28)

    init(device: DeviceStatus) {
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))

        let kindIcon = NSImageView(image: Self.kindImage(for: device.kind))
        kindIcon.translatesAutoresizingMaskIntoConstraints = false
        kindIcon.imageScaling = .scaleProportionallyDown

        let name = NSTextField(labelWithString: device.name)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.lineBreakMode = .byTruncatingTail
        name.font = .menuFont(ofSize: 0)
        name.textColor = .labelColor

        let percentage = NSTextField(labelWithString: "\(device.batteryPercent)%")
        percentage.translatesAutoresizingMaskIntoConstraints = false
        percentage.alignment = .right
        percentage.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        percentage.textColor = .labelColor

        let battery = NSImageView(image: Self.batteryImage(device.batteryPercent))
        battery.translatesAutoresizingMaskIntoConstraints = false
        battery.imageScaling = .scaleProportionallyDown

        addSubview(kindIcon)
        addSubview(name)
        addSubview(percentage)
        addSubview(battery)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.rowSize.width),
            heightAnchor.constraint(equalToConstant: Self.rowSize.height),
            kindIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            // SF Symbols sit optically a little high beside AppKit menu text.
            kindIcon.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            kindIcon.widthAnchor.constraint(equalToConstant: 16),
            kindIcon.heightAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: kindIcon.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: percentage.leadingAnchor, constant: -12),
            percentage.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentage.widthAnchor.constraint(equalToConstant: 42),
            battery.leadingAnchor.constraint(equalTo: percentage.trailingAnchor, constant: 5),
            battery.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            battery.centerYAnchor.constraint(equalTo: centerYAnchor),
            battery.widthAnchor.constraint(equalToConstant: 19),
            battery.heightAnchor.constraint(equalToConstant: 16),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(device.name), battery \(device.batteryPercent) percent")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private static func kindImage(for kind: DeviceKind) -> NSImage {
        let symbol: String
        let description: String
        switch kind {
        case .mouse:
            symbol = "computermouse"
            description = "Mouse"
        case .keyboard:
            symbol = "keyboard"
            description = "Keyboard"
        case .unknown:
            symbol = "dot.radiowaves.left.and.right"
            description = "Device"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        image.isTemplate = true
        return image
    }

    private static func batteryImage(_ percentage: Int) -> NSImage {
        let symbol = percentage > 75 ? "battery.100" : percentage > 50 ? "battery.75" : percentage > 25 ? "battery.50" : percentage > 10 ? "battery.25" : "battery.0"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Battery \(percentage) percent") ?? NSImage()
        image.isTemplate = true
        return image
    }
}
