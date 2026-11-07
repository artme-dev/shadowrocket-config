import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate {
    let store = StatusStore()
    var item: NSStatusItem!
    let popover = NSPopover()
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
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: StatusPanel(store: store,
            showDetails: { [weak self] in self?.openDetails() }, quit: { NSApp.terminate(nil) }))
        store.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if Bundle.main.object(forInfoDictionaryKey: "AINetworkPreviewPanel") as? Bool == true { self.openPreviewPanel() }
            else { self.openDetails() }
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
        windowMenu.addItem(withTitle: "Закрыть", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Изменить масштаб", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Все окна на передний план", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }
    func updateIcon() {
        let health = store.snapshot.health(at: Date())
        let symbol = health == .good ? "checkmark.shield" : health == .bad ? "exclamationmark.shield" : "shield.slash"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: store.snapshot.headline(at: Date()))!
        image.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "AI Network — \(store.snapshot.headline(at: Date()))"
    }
    @objc func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Подробнее…", action: #selector(openDetails), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Выйти из AI Network", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu; item.button?.performClick(nil); item.menu = nil
        } else if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }
    func showPanel() {
        guard let button = item.button else { return }
        store.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc func openDetails() {
        popover.performClose(nil)
        if let window = detailWindow { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let content = DetailView(store: store)
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = "AI Network"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 580, height: 700))
        window.minSize = NSSize(width: 560, height: 500)
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
    @objc func copyStatus() { store.copySummary() }
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
        let controller = NSHostingController(rootView: StatusPanel(store: store,
            showDetails: { [weak self] in self?.openDetails() }, quit: { NSApp.terminate(nil) }))
        let window = NSWindow(contentViewController: controller)
        window.title = "AI Network"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 360, height: controller.view.fittingSize.height))
        window.isReleasedWhenClosed = false; window.center(); previewWindow = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openDetails(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "AI Network", .applicationVersion: "1.0",
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
