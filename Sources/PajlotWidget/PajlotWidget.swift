import WidgetKit
import SwiftUI

@main
struct PajlotWidgetBundle: WidgetBundle {
    var body: some Widget { PajlotSessionsWidget() }
}

struct PajlotSessionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Copilot sessions")
        .description("See which sessions are working, done, or waiting for you.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Timeline

extension Font {
    /// Inter, bundled with the widget (registered once, since an extension can't rely on installed fonts).
    static func inter(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        _ = registerInter
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Inter-Bold"
        case .semibold: name = "Inter-SemiBold"
        case .medium: name = "Inter-Medium"
        default: name = "Inter-Regular"
        }
        return .custom(name, fixedSize: size)
    }
    private static let registerInter: Void = {
        for w in ["Regular", "Medium", "SemiBold", "Bold"] {
            if let url = Bundle.main.url(forResource: "Inter-\(w)", withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let snap = WidgetSnapshot.load()
        completion(Entry(date: .now, snapshot: context.isPreview && snap.sessions.isEmpty ? .sample : snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads the widget whenever a session changes; this is only a fallback.
        completion(Timeline(entries: [Entry(date: .now, snapshot: WidgetSnapshot.load())],
                            policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(sessions: [
        .init(id: "1", title: "Redesign onboarding flow", repo: "web-app", status: "needsInput", activity: "Needs you",
              question: "Should the skip button stay?", done: 3, total: 5, updatedAt: .now.addingTimeInterval(-60)),
        .init(id: "2", title: "Fix dark mode colours", repo: "design-system", status: "working", activity: "Editing files",
              question: nil, done: 1, total: 4, updatedAt: .now.addingTimeInterval(-20)),
        .init(id: "3", title: "Update README", repo: "docs", status: "idle", activity: "Done",
              question: nil, done: 2, total: 2, updatedAt: .now.addingTimeInterval(-900)),
    ], savedAt: .now)
}

// MARK: - Look (matches the popover's palette)

private enum Tint {
    // One warm accent, used only for what needs you. Everything else is monochrome.
    static func attention(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 1, green: 0.62, blue: 0.40) : Color(red: 0.89, green: 0.43, blue: 0.20) }
    static func working(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 112/255, green: 162/255, blue: 1) : Color(red: 62/255, green: 115/255, blue: 224/255) }
    static func ready(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 88/255, green: 204/255, blue: 170/255) : Color(red: 44/255, green: 150/255, blue: 124/255) }
    static func canvas(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 0.075, green: 0.075, blue: 0.085) : Color(red: 0.975, green: 0.975, blue: 0.98) }
    static func card(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 0.125, green: 0.125, blue: 0.14) : .white }

    static func status(_ raw: String, _ s: ColorScheme) -> Color {
        switch raw {
        case "needsInput": attention(s)
        case "working": working(s)
        case "idle": ready(s)
        default: .secondary
        }
    }
    static func label(_ raw: String) -> String {
        switch raw {
        case "needsInput": "Needs you"
        case "working": "Working"
        case "idle": "Done"
        default: "Closed"
        }
    }
}

// MARK: - Views

struct WidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private var sessions: [WidgetSnapshot.Session] { entry.snapshot.sessions }
    private var needs: Int { sessions.filter { $0.status == "needsInput" }.count }
    private var working: Int { sessions.filter { $0.status == "working" }.count }

    var body: some View {
        Group {
            if family == .systemSmall { small } else { list(max: family == .systemExtraLarge ? 8 : family == .systemLarge ? 5 : 2) }
        }
        .containerBackground(Tint.canvas(scheme), for: .widget)
    }

    // Small: the headline number and the session that matters most.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            if let top = sessions.first {
                Text(needs > 0 ? "\(needs)" : "\(working)")
                    .font(.inter(46, .bold))
                    .foregroundStyle(needs > 0 ? Tint.attention(scheme) : .primary)
                Text(needs > 0 ? "need you" : working > 0 ? "working" : "all done")
                    .font(.inter(14, .medium)).foregroundStyle(.secondary)
                Text(top.title).font(.inter(14, .semibold)).lineLimit(2).padding(.top, 2)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func list(max: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if sessions.isEmpty {
                Spacer(minLength: 0); empty.frame(maxWidth: .infinity); Spacer(minLength: 0)
            } else {
                ForEach(sessions.prefix(max)) { Row(session: $0, showQuestion: family == .systemLarge || family == .systemExtraLarge) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 5) {
            LogoMark().frame(width: 18, height: 18).foregroundStyle(scheme == .dark ? Color(white: 0.95) : Color(red: 0x23/255, green: 0x23/255, blue: 0x23/255)).widgetAccentable()
            Text("Pajlot").font(.inter(15, .semibold))
            Spacer(minLength: 0)
            if family != .systemSmall {
                if needs > 0 { Badge(text: "\(needs) need you", tint: Tint.attention(scheme)) }
                if working > 0 { Badge(text: "\(working) working", tint: .secondary) }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 3) {
            Image(systemName: "moon.zzz").font(.inter(22, .regular)).foregroundStyle(.secondary)
            Text("No active sessions").font(.inter(14, .regular)).foregroundStyle(.secondary)
        }
    }
}

private struct Badge: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text).font(.inter(12, .semibold)).foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

private struct Row: View {
    let session: WidgetSnapshot.Session
    let showQuestion: Bool
    @Environment(\.colorScheme) private var scheme

    static func ago(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: .now)
    }
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let tint = Tint.status(session.status, scheme)
        HStack(alignment: .top, spacing: 8) {
            Capsule().fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.title).font(.inter(14, .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.ago(session.updatedAt)).font(.inter(12, .regular)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(session.status == "working" ? session.activity : Tint.label(session.status))
                        .foregroundStyle(session.status == "needsInput" ? tint : .secondary)   // only the line carries the status colour
                    Text("· \(session.repo)").foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if session.total > 0 {
                        Text("\(session.done)/\(session.total)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.inter(12, .regular)).lineLimit(1)
                if showQuestion, let q = session.question {
                    Text(q).font(.inter(12, .regular)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            // In glass/tinted mode text is drawn white, so a solid white card would hide it.
            .fill(mode == .fullColor ? Tint.card(scheme) : Color.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .fixedSize(horizontal: false, vertical: true)
    }
}


/// The app logo (open ring, centre dot, small dot in the gap), same shapes as the menu bar icon.
private struct LogoMark: View {
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 18
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ringR = 6.4 * k, gapCenter = 135.0, gap = 90.0
            func pt(_ deg: Double, _ r: Double) -> CGPoint {
                let a = deg * .pi / 180
                return CGPoint(x: c.x + cos(a) * r, y: c.y - sin(a) * r)   // y is down on screen
            }
            var ring = Path()
            let start = gapCenter + gap / 2, sweep = 360 - gap
            ring.move(to: pt(start, ringR))
            for i in 1...90 { ring.addLine(to: pt(start + sweep * Double(i) / 90, ringR)) }
            ctx.stroke(ring, with: .foreground, style: StrokeStyle(lineWidth: 2.1 * k, lineCap: .round, lineJoin: .round))
            func dot(_ p: CGPoint, _ r: Double) {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .foreground)
            }
            dot(pt(gapCenter, ringR), 1.25 * k)
            dot(c, 2.2 * k)
        }
    }
}
