import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let store = StatusStore()
    var item: NSStatusItem!
    var panel: StatusGlassPanel?
    var localEventMonitor: Any?
    var previousApplication: NSRunningApplication?
    var detailWindow: NSWindow?
    var previewWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.object(forInfoDictionaryKey: "AINetworkPreviewDark") as? Bool == true {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        buildMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("AI Network: состояние AI-маршрутов")
        NotificationCenter.default.addObserver(self, selector: #selector(hidePanel),
            name: NSApplication.didResignActiveNotification, object: nil)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.dismissPanelRestoringFocus(); return nil }
            } else if event.window !== panel, event.window !== self.item.button?.window { self.hidePanel() }
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hidePanel),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        store.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if Bundle.main.object(forInfoDictionaryKey: "AINetworkPreviewPanel") as? Bool == true { self.openPreviewPanel() }
            else { self.showPanel() }
        }
    }
    func buildMenu() {
        let menu = NSMenu()
        let root = NSMenuItem(); menu.addItem(root)
        let app = NSMenu(); root.submenu = app
        app.addItem(withTitle: "Об AI Network", action: #selector(about), keyEquivalent: "")
        app.addItem(withTitle: "Статус сети", action: #selector(togglePanel), keyEquivalent: "1").target = self
        app.addItem(withTitle: "Подробнее…", action: #selector(openDetails), keyEquivalent: "2").target = self
        app.addItem(withTitle: "Обновить данные", action: #selector(reloadStatus), keyEquivalent: "r").target = self
        let copy = app.addItem(withTitle: "Скопировать сводку", action: #selector(copyStatus), keyEquivalent: "c")
        copy.keyEquivalentModifierMask = [.command, .shift]; copy.target = self
        app.addItem(NSMenuItem.separator())
        app.addItem(withTitle: "Выйти из AI Network", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editRoot = NSMenuItem(); menu.addItem(editRoot)
        let edit = NSMenu(title: "Правка"); editRoot.submenu = edit
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowRoot = NSMenuItem(); menu.addItem(windowRoot)
        let windowMenu = NSMenu(title: "Окно"); windowRoot.submenu = windowMenu
        windowMenu.addItem(withTitle: "Закрыть", action: #selector(closeCurrentWindow), keyEquivalent: "w").target = self
        windowMenu.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Изменить масштаб", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Все окна на передний план", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }
    func updateIcon() {
        let health = store.snapshot.health(at: Date())
        let symbol = health == .good ? "checkmark.shield" : health == .bad ? "exclamationmark.shield" : "exclamationmark.triangle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: store.snapshot.headline(at: Date()))!
        image.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "AI Network — \(store.snapshot.headline(at: Date()))\n\(store.age)"
        item.button?.setAccessibilityValue("\(store.snapshot.headline(at: Date())). \(store.age)")
    }
    @objc func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            hidePanel()
            let menu = NSMenu()
            menu.addItem(withTitle: "Подробнее…", action: #selector(openDetails), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Скопировать сводку", action: #selector(copyStatus), keyEquivalent: "").target = self
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Выйти из AI Network", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu; item.button?.performClick(nil); item.menu = nil
        } else if panel?.isVisible == true { dismissPanelRestoringFocus() } else { showPanel() }
    }
    @objc func hidePanel() {
        panel?.orderOut(nil)
        item.button?.highlight(false)
    }
    func dismissPanelRestoringFocus() {
        hidePanel()
        previousApplication?.activate(options: [])
    }
    @objc func closeCurrentWindow() {
        if panel?.isVisible == true { dismissPanelRestoringFocus() }
        else { NSApp.keyWindow?.performClose(nil) }
    }
    func showPanel() {
        guard let button = item.button, let statusWindow = button.window else { return }
        store.refresh()
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = frontmost }
        if panel == nil {
            let host = GlassHost(rootView: StatusPanel(store: store,
                showDetails: { [weak self] in self?.openDetails() }, quit: { NSApp.terminate(nil) }))
            let window = StatusGlassPanel(contentRect: NSRect(origin: .zero, size: host.preferredContentSize),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "AI Network"
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.level = .popUpMenu
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.contentViewController = host
            window.animationBehavior = .utilityWindow
            window.onDismiss = { [weak self] in self?.dismissPanelRestoringFocus() }
            panel = window
        }
        guard let panel else { return }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = statusWindow.screen ?? NSScreen.main!
        let visible = screen.visibleFrame
        let x = min(max(anchor.maxX - panel.frame.width, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        let y = max(visible.minY + 8, anchor.minY - panel.frame.height - 7)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        button.highlight(true)
    }
    @objc func openDetails() {
        hidePanel()
        if let window = detailWindow { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let controller = GlassHost(rootView: DetailView(store: store), size: NSSize(width: 520, height: 680))
        let window = NSWindow(contentViewController: controller)
        window.title = "AI Network"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isOpaque = false; window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .vibrantDark)
        window.setContentSize(NSSize(width: 520, height: 680))
        window.minSize = NSSize(width: 500, height: 500)
        let toolbar = NSToolbar(identifier: "AINetwork.DetailToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        detailWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    @objc func reloadStatus() { store.refresh() }
    @objc func copyStatus() {
        store.copySummary()
        let copy = detailWindow?.toolbar?.items.first { $0.itemIdentifier.rawValue == "copy" }
        copy?.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Сводка скопирована")
        copy?.toolTip = "Сводка скопирована"
        copy?.label = "Сводка скопирована"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak copy] in
            copy?.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Скопировать сводку")
            copy?.toolTip = "Скопировать сводку"
            copy?.label = "Скопировать сводку"
        }
    }
    @objc func revealLog() { store.showLog() }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("refresh"), .init("copy"), .init("log")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let values: [String: (String, String, Selector)] = [
            "refresh": ("Обновить данные", "arrow.clockwise", #selector(reloadStatus)),
            "copy": ("Скопировать сводку", "doc.on.doc", #selector(copyStatus)),
            "log": ("Показать журнал в Finder", "folder", #selector(revealLog))]
        guard let (label, symbol, action) = values[identifier.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label; item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self; item.action = action
        return item
    }
    // Local visual QA uses the exact popover content in a standard window; no live data is modified.
    func openPreviewPanel() {
        let controller = GlassHost(rootView: StatusPanel(store: store,
            showDetails: { [weak self] in self?.openDetails() }, quit: { NSApp.terminate(nil) }))
        let window = NSWindow(contentViewController: controller)
        window.title = "AI Network"
        window.styleMask = [.titled, .closable]
        window.setContentSize(controller.preferredContentSize)
        window.isReleasedWhenClosed = false; window.center(); previewWindow = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(closeCurrentWindow) { return panel?.isVisible == true || NSApp.keyWindow != nil }
        if menuItem.action == #selector(reloadStatus) { return !store.refreshing }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = localEventMonitor { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let panel, panel.isVisible { panel.makeKeyAndOrderFront(nil) }
        else if let window = detailWindow, window.isVisible { window.makeKeyAndOrderFront(nil) }
        else { showPanel() }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "AI Network", .applicationVersion: "1.1",
            .credits: NSAttributedString(string: "Личный монитор AI-маршрутов. Только просмотр.\nWatcher, firewall и VPN работают независимо.")])
    }
}

@main struct Entry {
    static func main() {
        if CommandLine.arguments.contains("--self-test") { exit(runModelTests()) }
        if CommandLine.arguments.contains("--read-snapshot") {
            print(loadSnapshot(paths: .current).diagnostic(at: Date())); return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
