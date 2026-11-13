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
    static func accent(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 150/255, green: 136/255, blue: 1) : Color(red: 99/255, green: 82/255, blue: 238/255) }
    static func attention(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 1, green: 159/255, blue: 67/255) : Color(red: 232/255, green: 110/255, blue: 18/255) }
    static func ready(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 64/255, green: 208/255, blue: 140/255) : Color(red: 22/255, green: 156/255, blue: 98/255) }
    static func canvas(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 24/255, green: 24/255, blue: 27/255) : Color(red: 244/255, green: 244/255, blue: 247/255) }
    static func card(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 36/255, green: 36/255, blue: 40/255) : .white }

    static func status(_ raw: String, _ s: ColorScheme) -> Color {
        switch raw {
        case "needsInput": attention(s)
        case "working": accent(s)
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
            if family == .systemSmall { small } else { list(max: family == .systemExtraLarge ? 10 : family == .systemLarge ? 6 : 3) }
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
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Tint.status(needs > 0 ? "needsInput" : working > 0 ? "working" : "idle", scheme))
                Text(needs > 0 ? "need you" : working > 0 ? "working" : "all done")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(top.title).font(.caption2).lineLimit(2).padding(.top, 2)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func list(max: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
            Image(systemName: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(Tint.accent(scheme))
            Text("Pajlot").font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            if family != .systemSmall {
                if needs > 0 { Badge(text: "\(needs) need you", tint: Tint.attention(scheme)) }
                if working > 0 { Badge(text: "\(working) working", tint: Tint.accent(scheme)) }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 3) {
            Image(systemName: "moon.zzz").font(.title3).foregroundStyle(.secondary)
            Text("No active sessions").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct Badge: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

private struct Row: View {
    let session: WidgetSnapshot.Session
    let showQuestion: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tint = Tint.status(session.status, scheme)
        HStack(alignment: .top, spacing: 8) {
            Capsule().fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(session.updatedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        .frame(maxWidth: 70, alignment: .trailing)
                }
                HStack(spacing: 4) {
                    Text(session.status == "working" ? session.activity : Tint.label(session.status))
                        .foregroundStyle(tint)
                    Text("· \(session.repo)").foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if session.total > 0 {
                        Text("\(session.done)/\(session.total)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.caption2).lineLimit(1)
                if showQuestion, let q = session.question {
                    Text(q).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Tint.card(scheme)))
        .fixedSize(horizontal: false, vertical: true)
    }
}
