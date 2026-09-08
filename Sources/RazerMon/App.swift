import AppKit
import Foundation
import IOKit.hid
import ServiceManagement

@main
final class RazerMonApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var devices: [DeviceStatus] = []
    private var cachedDevices: [String: CachedDeviceStatus] = [:]
    private var errorMessage: String?
    private var isRefreshing = false
    private var refreshRequestedWhileRefreshing = false
    private var batteryRefreshRequestedWhileRefreshing = false
    private var refreshTimer: Timer?
    private var menuTrackingTimer: Timer?
    private var permissionTimer: Timer?
    private var powerObservers: [NSObjectProtocol] = []
    private var isPreparingForSleep = false
    private var permissionGuide: PermissionGuideWindowController?
    private var permissionPromptIsShowing = false
    private let deviceRegistry = HIDDeviceRegistry()
    private var lastRefreshDate: Date?

    private enum RefreshPolicy {
        static let openMenuInterval: TimeInterval = 15
        static let batteryCacheInterval: TimeInterval = 5 * 60
        static let backgroundInterval: TimeInterval = 15 * 60
        static let permissionCheckInterval: TimeInterval = 2
    }

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
        installPowerObservers()

        deviceRegistry.onChange = { [weak self] _ in
            self?.refreshIfAllowed(force: true)
        }

        if hasInputMonitoringPermission {
            startDeviceRegistry()
        } else {
            showPermissionPrompt()
            startPermissionTimer()
        }
        let timer = Timer(timeInterval: RefreshPolicy.backgroundInterval, repeats: true) {
            [weak self] _ in self?.refreshIfAllowed(minimumInterval: RefreshPolicy.backgroundInterval)
        }
        timer.tolerance = RefreshPolicy.backgroundInterval * 0.1
        RunLoop.main.add(timer, forMode: .default)
        refreshTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        menuTrackingTimer?.invalidate()
        permissionTimer?.invalidate()
        for observer in powerObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        powerObservers.removeAll()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshIfAllowed(force: true)
        startMenuTrackingTimer()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuTrackingTimer?.invalidate()
        menuTrackingTimer = nil
    }
    @objc private func refreshFromMenu() { refreshIfAllowed(force: true, forceBatteryRefresh: true) }
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
            alert.messageText = L10n.text("launch_at_login.error.title")
            alert.informativeText = L10n.format("launch_at_login.error.message", error.localizedDescription)
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
        permissionTimer?.invalidate()
        permissionTimer = nil
        permissionGuide?.showAuthorizedState()
        startDeviceRegistry()
        rebuildMenu()
    }

    private func startPermissionTimer() {
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: RefreshPolicy.permissionCheckInterval, repeats: true) {
            [weak self] _ in self?.permissionDidChange()
        }
        timer.tolerance = RefreshPolicy.permissionCheckInterval * 0.1
        RunLoop.main.add(timer, forMode: .default)
        permissionTimer = timer
    }

    private func installPowerObservers() {
        let notifications = NSWorkspace.shared.notificationCenter
        powerObservers = [
            notifications.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isPreparingForSleep = true
                self?.menuTrackingTimer?.invalidate()
                self?.menuTrackingTimer = nil
            },
            notifications.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.isPreparingForSleep = false
                self.refreshIfAllowed(force: true)
            }
        ]
    }

    private func startDeviceRegistry() {
        guard !deviceRegistry.isStarted else { return }
        do {
            try deviceRegistry.start()
        } catch {
            errorMessage = String(describing: error)
            rebuildMenu()
        }
    }

    private func showPermissionPrompt() {
        guard !hasInputMonitoringPermission, !permissionPromptIsShowing else { return }
        permissionPromptIsShowing = true
        let alert = NSAlert()
        alert.messageText = L10n.text("permission.alert.title")
        alert.informativeText = L10n.text("permission.alert.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text("permission.alert.open_settings"))
        alert.addButton(withTitle: L10n.text("permission.alert.not_now"))
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

    private func refreshIfAllowed(
        minimumInterval: TimeInterval = 0,
        force: Bool = false,
        forceBatteryRefresh: Bool = false
    ) {
        guard !isPreparingForSleep else { return }
        guard hasInputMonitoringPermission else { rebuildMenu(); return }
        if isRefreshing {
            if force { refreshRequestedWhileRefreshing = true }
            if forceBatteryRefresh { batteryRefreshRequestedWhileRefreshing = true }
            return
        }
        if !force, let lastRefreshDate, Date().timeIntervalSince(lastRefreshDate) < minimumInterval { return }
        refresh(forceBatteryRefresh: forceBatteryRefresh)
    }

    private func startMenuTrackingTimer() {
        guard menuTrackingTimer == nil else { return }
        let timer = Timer(timeInterval: RefreshPolicy.openMenuInterval, repeats: true) { [weak self] _ in
            self?.refreshIfAllowed(force: true)
        }
        timer.tolerance = RefreshPolicy.openMenuInterval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        menuTrackingTimer = timer
    }

    private func refresh(forceBatteryRefresh: Bool = false) {
        guard !isRefreshing else { return }
        let connectedProductIDs = deviceRegistry.connectedProductIDs
        guard !connectedProductIDs.isEmpty else {
            let menuNeedsUpdate = !devices.isEmpty || errorMessage != nil
            devices = []
            cachedDevices = [:]
            errorMessage = nil
            lastRefreshDate = Date()
            if menuNeedsUpdate { rebuildMenu() }
            return
        }
        isRefreshing = true
        let cachedDevices = cachedDevices
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result {
                try RazerMonitor.readDevices(
                    connectedProductIDs: connectedProductIDs,
                    cachedDevices: cachedDevices,
                    batteryMaximumAge: RefreshPolicy.batteryCacheInterval,
                    forceBatteryRefresh: forceBatteryRefresh,
                    onDiscovery: { discoveredDevices in
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.devices != discoveredDevices else { return }
                            self.devices = discoveredDevices
                            self.rebuildMenu()
                        }
                    }
                )
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.lastRefreshDate = Date()
                let previousDevices = self.devices
                let previousError = self.errorMessage
                switch result {
                case .success(let cachedDevices):
                    self.cachedDevices = Dictionary(
                        uniqueKeysWithValues: cachedDevices.map { ($0.status.serialNumber, $0) }
                    )
                    self.devices = cachedDevices.map(\.status)
                    self.errorMessage = nil
                case .failure(let error): self.devices = []; self.errorMessage = String(describing: error)
                }
                if self.devices != previousDevices || self.errorMessage != previousError {
                    self.rebuildMenu()
                }
                if self.refreshRequestedWhileRefreshing {
                    let forceBatteryRefresh = self.batteryRefreshRequestedWhileRefreshing
                    self.refreshRequestedWhileRefreshing = false
                    self.batteryRefreshRequestedWhileRefreshing = false
                    self.refreshIfAllowed(force: true, forceBatteryRefresh: forceBatteryRefresh)
                }
            }
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        if !hasInputMonitoringPermission {
            addDisabled(L10n.text("menu.permission_required"))
            let permission = NSMenuItem(title: L10n.text("menu.enable_input_monitoring"), action: #selector(showPermissionFromMenu), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        } else if devices.isEmpty {
            addDisabled(isRefreshing ? L10n.text("menu.reading_devices") : (errorMessage ?? L10n.text("menu.no_devices")))
        } else {
            for device in devices {
                let batteryText = device.batteryPercent.map { "\($0)%" } ?? L10n.text("menu.reading_battery")
                let item = NSMenuItem(title: L10n.format("menu.device_summary", device.name, batteryText), action: nil, keyEquivalent: "")
                item.view = DeviceMenuItemView(device: device)
                item.toolTip = L10n.format("menu.serial_number", device.serialNumber)
                // A disabled NSMenuItem is always shown in gray. These entries
                // are informational, but the connected devices are healthy.
                item.isEnabled = true
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: L10n.text("menu.refresh"), action: #selector(refreshFromMenu), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = hasInputMonitoringPermission
        menu.addItem(refresh)
        let launchAtLogin = NSMenuItem(title: L10n.text("menu.launch_at_login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.isEnabled = true
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval {
            launchAtLogin.toolTip = L10n.text("menu.launch_at_login.approval_required")
        }
        menu.addItem(launchAtLogin)
        menu.addItem(.separator())
        let exit = NSMenuItem(title: L10n.text("menu.exit"), action: #selector(exitApp), keyEquivalent: "q")
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

        let percentage = NSTextField(labelWithString: device.batteryPercent.map { "\($0)%" } ?? "—")
        percentage.translatesAutoresizingMaskIntoConstraints = false
        percentage.alignment = .right
        percentage.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        percentage.textColor = .labelColor

        let battery = NSImageView(image: Self.batteryImage(device.batteryPercent ?? 0))
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
        if let batteryPercent = device.batteryPercent {
            setAccessibilityLabel(L10n.format("accessibility.device_battery", device.name, batteryPercent))
        } else {
            setAccessibilityLabel(L10n.format("accessibility.device_reading", device.name))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private static func kindImage(for kind: DeviceKind) -> NSImage {
        let symbol: String
        let description: String
        switch kind {
        case .mouse:
            symbol = "computermouse"
            description = L10n.text("accessibility.mouse")
        case .keyboard:
            symbol = "keyboard"
            description = L10n.text("accessibility.keyboard")
        case .unknown:
            symbol = "dot.radiowaves.left.and.right"
            description = L10n.text("accessibility.device")
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        image.isTemplate = true
        return image
    }

    private static func batteryImage(_ percentage: Int) -> NSImage {
        let symbol = percentage > 75 ? "battery.100" : percentage > 50 ? "battery.75" : percentage > 25 ? "battery.50" : percentage > 10 ? "battery.25" : "battery.0"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: L10n.format("accessibility.battery", percentage)) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
