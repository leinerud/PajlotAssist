import SwiftUI
import AppKit

@main
struct PajlotAssistApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: SessionStore
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var workingCount: Int { store.sessions.filter { $0.status == .working }.count }

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: icon)
            if store.activeCount > 0 { Text("\(store.activeCount)") }
        }
        .onReceive(timer) { _ in
            if let d = store.doneAt, Date().timeIntervalSince(d) > 120 { store.doneAt = nil }
        }
    }

    private var icon: NSImage {
        if store.needsInputCount > 0 {
            // Blink the speech bubble so it catches the eye.
            let name = "bubble.left.fill"
            let img = NSImage(systemSymbolName: name, accessibilityDescription: "Copilot needs you") ?? NSImage()
            img.isTemplate = true
            return img
        }
        if workingCount > 0 { return Self.spinner(frame: 0) }
        if store.doneAt != nil {
            let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copilot finished") ?? NSImage()
            img.isTemplate = true
            return img
        }
        let name = store.activeCount > 0 ? "sparkles" : "moon.zzz"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Copilot") ?? NSImage()
        img.isTemplate = true
        return img
    }

    /// A sparkle in the middle of a ring with a rotating arc, so activity is visible at a glance.
    static func spinner(frame: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke(); NSColor.black.setFill()
            let c = NSPoint(x: rect.midX, y: rect.midY)
            let ring = NSBezierPath()
            ring.appendArc(withCenter: c, radius: 7.5, startAngle: 0, endAngle: 360)
            ring.lineWidth = 1; NSColor.black.withAlphaComponent(0.3).setStroke(); ring.stroke()
            let start = CGFloat(-frame * 30)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: 7.5, startAngle: start, endAngle: start - 100, clockwise: true)
            arc.lineWidth = 2; arc.lineCapStyle = .round; NSColor.black.setStroke(); arc.stroke()
            // 4-point sparkle
            let r: CGFloat = 3.6, k: CGFloat = 0.9
            let star = NSBezierPath()
            star.move(to: NSPoint(x: c.x, y: c.y + r))
            star.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + k, y: c.y + k), controlPoint2: NSPoint(x: c.x + k, y: c.y + k))
            star.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + k, y: c.y - k), controlPoint2: NSPoint(x: c.x + k, y: c.y - k))
            star.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - k, y: c.y - k), controlPoint2: NSPoint(x: c.x - k, y: c.y - k))
            star.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - k, y: c.y + k), controlPoint2: NSPoint(x: c.x - k, y: c.y + k))
            star.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
