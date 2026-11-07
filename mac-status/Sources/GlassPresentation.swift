import AppKit
import SwiftUI

// Preserve actual symbol colors on white disks; automatic vibrancy washes them out.
final class GlassHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}

/// One actual system glass layer, with no opaque hosting or popover background underneath.
final class GlassHost<Content: View>: NSViewController {
    let hosting: GlassHostingView<Content>
    let glass = NSGlassEffectView()
    init(rootView: Content, size: NSSize? = nil, cornerRadius: CGFloat = 18) {
        hosting = GlassHostingView(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        let fitting = size ?? hosting.fittingSize
        glass.frame = NSRect(origin: .zero, size: fitting)
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.appearance = NSAppearance(named: .vibrantDark)
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        // Keep foreground out of the glass's automatic vibrancy pass. This preserves
        // readable SF text and true system green on white symbol disks.
        hosting.appearance = NSAppearance(named: .darkAqua)
        let container = NSView(frame: glass.frame)
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        container.addSubview(hosting)
        self.view = container
        preferredContentSize = fitting
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
}

final class StatusGlassPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil); onDismiss?() }
}
