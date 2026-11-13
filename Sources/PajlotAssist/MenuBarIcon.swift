import AppKit
import Combine

/// What the menu bar icon is telling the user right now.
enum MenuBarIconMode: Equatable {
    case idle        // app is running, nothing happening: the plain logo, with a heartbeat now and then
    case working     // a session is working: the ring spins
    case needsInput  // a session is waiting for you: the small dot pulses and pops out
    case done        // a session just finished: the ring closes and the dot becomes a checkmark

    var accessibilityLabel: String {
        switch self {
        case .idle: "Pajlot Assist"
        case .working: "A session is working"
        case .needsInput: "A session needs you"
        case .done: "A session finished"
        }
    }
}

/// Draws the app logo (open ring, centre dot, small satellite dot in the gap) at menu bar size,
/// in any pose, so each state can be animated from the same shapes.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)
    private static let ringRadius: CGFloat = 6.4
    private static let ringWidth: CGFloat = 2.1
    private static let dotRadius: CGFloat = 2.2
    private static let satRadius: CGFloat = 1.25
    private static let gapCenter: CGFloat = 135   // degrees; the opening sits top-left, like the logo

    struct Pose {
        var rotation: CGFloat = 0    // degrees, applied to ring + satellite (negative = clockwise)
        var gap: CGFloat = 90        // size of the ring's opening in degrees
        var satScale: CGFloat = 1
        var satOffset: CGFloat = 0   // pushes the satellite outward from the ring
        var dotScale: CGFloat = 1
        var check: CGFloat = 0       // 0 = no checkmark, 1 = fully drawn
    }

    // MARK: Poses over time

    /// `t` is seconds since the mode started.
    static func pose(for mode: MenuBarIconMode, at t: TimeInterval) -> Pose {
        var p = Pose()
        switch mode {
        case .idle:
            // A soft heartbeat every few seconds, so you can see the app is alive.
            let phase = t.truncatingRemainder(dividingBy: heartbeatEvery)
            if phase < heartbeatLength {
                let s = sin(.pi * phase / heartbeatLength)
                p.dotScale = 1 + 0.3 * s
                p.satOffset = 0.8 * s
            }
        case .working:
            p.rotation = -CGFloat(t) * 260
            p.gap = 90 + 35 * CGFloat(sin(t * 2 * .pi / 1.4))
        case .needsInput:
            let s = CGFloat((sin(t * 2 * .pi / 1.1 - .pi / 2) + 1) / 2)
            p.satScale = 1 + 0.85 * s
            p.satOffset = 0.9 * s
            p.dotScale = 1 - 0.18 * s
        case .done:
            let close = ease(clamp(t / 0.45))
            p.gap = 90 * (1 - close)
            p.satScale = 1 - close
            p.dotScale = 1 - ease(clamp(t / 0.3))
            p.check = ease(clamp((t - 0.25) / 0.4))
        }
        return p
    }

    static let heartbeatEvery: TimeInterval = 6
    static let heartbeatLength: TimeInterval = 0.7
    static let doneAnimationLength: TimeInterval = 0.7

    /// Whether `mode` at time `t` needs another frame soon.
    static func isAnimating(_ mode: MenuBarIconMode, at t: TimeInterval) -> Bool {
        switch mode {
        case .working, .needsInput: true
        case .done: t < doneAnimationLength
        case .idle: t.truncatingRemainder(dividingBy: heartbeatEvery) < heartbeatLength
        }
    }

    // MARK: Drawing

    static func image(_ p: Pose, description: String) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke(); NSColor.black.setFill()
            let c = NSPoint(x: rect.midX, y: rect.midY)

            // Ring with its opening.
            let ring = NSBezierPath()
            // The round caps already meet below ~19°, so draw a clean circle instead of a nub.
            if p.gap < 19 {
                ring.appendArc(withCenter: c, radius: ringRadius, startAngle: 0, endAngle: 360)
            } else {
                let gc = gapCenter + p.rotation
                ring.appendArc(withCenter: c, radius: ringRadius,
                               startAngle: gc + p.gap / 2, endAngle: gc - p.gap / 2 + 360, clockwise: false)
            }
            ring.lineWidth = ringWidth; ring.lineCapStyle = .round; ring.stroke()

            // Satellite dot sitting in the opening.
            let sr = satRadius * p.satScale
            if sr > 0.15 {
                let a = (gapCenter + p.rotation) * .pi / 180
                let d = ringRadius + p.satOffset
                let sc = NSPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                NSBezierPath(ovalIn: NSRect(x: sc.x - sr, y: sc.y - sr, width: sr * 2, height: sr * 2)).fill()
            }

            // Centre dot.
            let dr = dotRadius * p.dotScale
            if dr > 0.15 {
                NSBezierPath(ovalIn: NSRect(x: c.x - dr, y: c.y - dr, width: dr * 2, height: dr * 2)).fill()
            }

            // Checkmark, drawn stroke by stroke.
            if p.check > 0 {
                let a = NSPoint(x: c.x - 2.7, y: c.y + 0.1)
                let b = NSPoint(x: c.x - 0.9, y: c.y - 1.8)
                let e = NSPoint(x: c.x + 2.8, y: c.y + 2.0)
                let l1 = hypot(b.x - a.x, b.y - a.y), l2 = hypot(e.x - b.x, e.y - b.y)
                let drawn = (l1 + l2) * p.check
                let path = NSBezierPath()
                path.move(to: a)
                if drawn <= l1 {
                    let f = drawn / l1
                    path.line(to: NSPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
                } else {
                    let f = (drawn - l1) / l2
                    path.line(to: b)
                    path.line(to: NSPoint(x: b.x + (e.x - b.x) * f, y: b.y + (e.y - b.y) * f))
                }
                path.lineWidth = 1.8; path.lineCapStyle = .round; path.lineJoinStyle = .round
                path.stroke()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = description
        return img
    }

    private static func clamp(_ x: Double) -> CGFloat { CGFloat(min(1, max(0, x))) }
    private static func ease(_ x: CGFloat) -> CGFloat { 1 - pow(1 - x, 3) }
}

/// Drives the icon's frames. Only ticks while something is actually moving, and sleeps
/// between idle heartbeats, so the menu bar stays cheap.
@MainActor
final class MenuBarIconAnimator: ObservableObject {
    @Published private(set) var image: NSImage = MenuBarIcon.image(.init(), description: "Pajlot Assist")
    private var mode: MenuBarIconMode = .idle
    private var modeStart = Date()
    private var timer: Timer?

    func set(_ newMode: MenuBarIconMode) {
        guard newMode != mode || timer == nil else { return }
        if newMode != mode { mode = newMode; modeStart = Date() }
        render()
        schedule()
    }

    private var elapsed: TimeInterval { Date().timeIntervalSince(modeStart) }

    private func render() {
        image = MenuBarIcon.image(MenuBarIcon.pose(for: mode, at: elapsed), description: mode.accessibilityLabel)
    }

    private func schedule() {
        timer?.invalidate(); timer = nil
        let t = elapsed
        let delay: TimeInterval
        if MenuBarIcon.isAnimating(mode, at: t) {
            delay = 1.0 / 24
        } else if mode == .idle {
            // Wake up for the next heartbeat.
            delay = MenuBarIcon.heartbeatEvery - t.truncatingRemainder(dividingBy: MenuBarIcon.heartbeatEvery)
        } else {
            return // done: resting on the checkmark
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.render(); self?.schedule() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
