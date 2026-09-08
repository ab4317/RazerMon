import AppKit
import CoreGraphics

final class PermissionGuideWindowController {
    var onBack: (() -> Void)?

    private let trackingInterval: TimeInterval = 0.15
    private var panel: NSPanel?
    private var workspaceObserver: NSObjectProtocol?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    private var orderedWindowNumber: Int?
    private var trackingTimer: Timer?
    private var isShowing = false

    private enum Layout {
        static let panelWidth: CGFloat = 530
        static let panelHeight: CGFloat = 109
        static let screenHorizontalInset: CGFloat = 16
        static let screenBottomInset: CGFloat = 12
        static let windowBottomOverlap: CGFloat = 6
        static let contentLeadingInset: CGFloat = 26
        static let contentTrailingInset: CGFloat = 28
        static let sidebarWidthRatio: CGFloat = 0.29
        static let sidebarWidthMin: CGFloat = 214
        static let sidebarWidthMax: CGFloat = 272
    }

    private struct SystemSettingsWindowContext {
        let bounds: CGRect
        let windowNumber: Int
    }

    func openSettingsAndPresent() {
        isShowing = true
        let panel = panel ?? makePanel()
        self.panel = panel
        installObserversIfNeeded()
        startTrackingTimer()

        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
        ]
        _ = urls.compactMap(URL.init(string:)).first(where: { NSWorkspace.shared.open($0) })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.updatePanelVisibility() }
    }

    func showAuthorizedState() {
        hide()
    }

    func hide() {
        isShowing = false
        stopTrackingTimer()
        removeObservers()
        panel?.orderOut(nil)
        orderedWindowNumber = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: Layout.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentView = PermissionAccessoryPanelView { [weak self] in self?.onBack?() }
        return panel
    }

    private func installObserversIfNeeded() {
        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.updatePanelVisibility() }
        }
        if globalDragMonitor == nil {
            globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] _ in
                self?.refreshPosition()
            }
        }
        if localDragMonitor == nil {
            localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.refreshPosition()
                return event
            }
        }
    }

    private func removeObservers() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let globalDragMonitor {
            NSEvent.removeMonitor(globalDragMonitor)
            self.globalDragMonitor = nil
        }
        if let localDragMonitor {
            NSEvent.removeMonitor(localDragMonitor)
            self.localDragMonitor = nil
        }
    }

    private func startTrackingTimer() {
        stopTrackingTimer()
        let timer = Timer(timeInterval: trackingInterval, repeats: true) { [weak self] _ in
            self?.updatePanelVisibility()
            self?.refreshPosition()
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func stopTrackingTimer() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func updatePanelVisibility() {
        guard isShowing, let panel else { return }
        guard isSystemSettingsFrontmost, let context = systemSettingsWindowContext() else {
            panel.orderOut(nil)
            return
        }
        orderedWindowNumber = context.windowNumber
        position(panel: panel, windowBounds: context.bounds)
        panel.order(.above, relativeTo: context.windowNumber)
    }

    private func refreshPosition() {
        guard isShowing, let panel, panel.isVisible, let context = systemSettingsWindowContext() else { return }
        orderedWindowNumber = context.windowNumber
        position(panel: panel, windowBounds: context.bounds)
    }

    private func position(panel: NSPanel, windowBounds: CGRect) {
        guard let origin = preferredPanelOrigin(for: panel.frame.size, windowBounds: windowBounds) else { return }
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func preferredPanelOrigin(for panelSize: CGSize, windowBounds: CGRect) -> CGPoint? {
        let visibleFrame = targetVisibleScreenFrame(for: windowBounds) ?? windowBounds
        let trackRect = systemSettingsContentTrackRect(in: windowBounds)
        let x = clamp(
            trackRect.midX - panelSize.width / 2,
            lower: visibleFrame.minX + Layout.screenHorizontalInset,
            upper: visibleFrame.maxX - panelSize.width - Layout.screenHorizontalInset
        )
        let desiredY = windowBounds.minY - panelSize.height + Layout.windowBottomOverlap
        let y = max(visibleFrame.minY + Layout.screenBottomInset, desiredY)
        return CGPoint(x: x, y: y)
    }

    private func systemSettingsContentTrackRect(in windowBounds: CGRect) -> CGRect {
        let sidebarWidth = clamp(
            windowBounds.width * Layout.sidebarWidthRatio,
            lower: Layout.sidebarWidthMin,
            upper: Layout.sidebarWidthMax
        )
        let contentMinX = min(
            windowBounds.maxX - Layout.contentTrailingInset - 1,
            windowBounds.minX + sidebarWidth + Layout.contentLeadingInset
        )
        let contentMaxX = max(contentMinX + 1, windowBounds.maxX - Layout.contentTrailingInset)
        return CGRect(x: contentMinX, y: windowBounds.minY, width: contentMaxX - contentMinX, height: windowBounds.height)
    }

    private func targetVisibleScreenFrame(for rect: CGRect) -> CGRect? {
        NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) })?.visibleFrame
    }

    private func appKitRect(fromCGWindowBounds bounds: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { screen in
            CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.frame.height).intersects(bounds)
        }) ?? NSScreen.main else { return bounds }
        return CGRect(x: bounds.minX, y: screen.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    private var isSystemSettingsFrontmost: Bool {
        let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return identifier == "com.apple.systempreferences" || identifier == "com.apple.SystemSettings"
    }

    private func systemSettingsWindowContext() -> SystemSettingsWindowContext? {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.systempreferences" || $0.bundleIdentifier == "com.apple.SystemSettings"
        }), let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let windows = windowInfoList.compactMap { info -> (SystemSettingsWindowContext, Int)? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == runningApp.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let windowNumber = info[kCGWindowNumber as String] as? Int,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { return nil }
            let appKitBounds = appKitRect(fromCGWindowBounds: bounds)
            return (SystemSettingsWindowContext(bounds: appKitBounds, windowNumber: windowNumber), Int(appKitBounds.width * appKitBounds.height))
        }
        return windows.sorted { $0.1 > $1.1 }.first?.0
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return lower }
        return min(max(value, lower), upper)
    }
}

final class PermissionAccessoryPanelView: NSView {
    private let onBack: () -> Void

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        let materialView = NSVisualEffectView()
        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 20
        materialView.layer?.masksToBounds = true
        materialView.layer?.borderWidth = 0.5
        materialView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
        addSubview(materialView)

        let tintView = NSView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8).cgColor
        materialView.addSubview(tintView)

        let backChrome = NSView()
        backChrome.translatesAutoresizingMaskIntoConstraints = false
        backChrome.wantsLayer = true
        backChrome.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        backChrome.layer?.cornerRadius = 16
        materialView.addSubview(backChrome)

        let backButton = AccessoryBackButton(target: self, action: #selector(handleBack))
        backChrome.addSubview(backButton)

        let arrow = NSImageView()
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: L10n.text("permission.guide.drag_upward"))
        arrow.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        arrow.contentTintColor = .systemBlue

        let instructionLabel = NSTextField(labelWithString: L10n.text("permission.guide.instruction"))
        instructionLabel.font = .systemFont(ofSize: 14, weight: .medium)
        instructionLabel.textColor = NSColor(calibratedWhite: 0.4, alpha: 1)
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.lineBreakMode = .byTruncatingTail
        instructionLabel.maximumNumberOfLines = 1
        instructionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let dragTileView = DraggableAppTileView()
        dragTileView.translatesAutoresizingMaskIntoConstraints = false

        materialView.addSubview(arrow)
        materialView.addSubview(instructionLabel)
        materialView.addSubview(dragTileView)

        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: leadingAnchor), materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.topAnchor.constraint(equalTo: topAnchor), materialView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor), tintView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: materialView.topAnchor), tintView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor),
            backChrome.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 18),
            backChrome.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 52),
            backChrome.widthAnchor.constraint(equalToConstant: 32), backChrome.heightAnchor.constraint(equalToConstant: 32),
            backButton.centerXAnchor.constraint(equalTo: backChrome.centerXAnchor), backButton.centerYAnchor.constraint(equalTo: backChrome.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 14), backButton.heightAnchor.constraint(equalToConstant: 14),
            arrow.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 35), arrow.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 10),
            arrow.widthAnchor.constraint(equalToConstant: 28), arrow.heightAnchor.constraint(equalToConstant: 28),
            instructionLabel.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 10),
            instructionLabel.centerYAnchor.constraint(equalTo: arrow.centerYAnchor),
            instructionLabel.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -22),
            dragTileView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 64),
            dragTileView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -21),
            dragTileView.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 47),
            dragTileView.heightAnchor.constraint(equalToConstant: 43)
        ])
    }

    @objc private func handleBack() { onBack() }
}

final class DraggableAppTileView: NSView, NSDraggingSource {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.86, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        RazerIcon.appImage.draw(in: CGRect(x: 12, y: 8, width: 28, height: 28))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.26, alpha: 1)
        ]
        "RazerMon".draw(at: CGPoint(x: 52, y: 12), withAttributes: attributes)
    }

    override func mouseDragged(with event: NSEvent) {
        let bundleURL = Bundle.main.bundleURL
        let draggingItem = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        draggingItem.setDraggingFrame(bounds, contents: snapshotImage())
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    private func snapshotImage() -> NSImage {
        let bitmap = bitmapImageRepForCachingDisplay(in: bounds) ?? NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

final class AccessoryBackButton: NSButton {
    override var isHighlighted: Bool { didSet { alphaValue = isHighlighted ? 0.66 : 1 } }

    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        focusRingType = .none
        image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: L10n.text("accessibility.back"))
        contentTintColor = NSColor.labelColor.withAlphaComponent(0.72)
        (cell as? NSButtonCell)?.imagePosition = .imageOnly
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
