import SwiftUI
import AppKit

// MARK: - Design tokens

/// One small palette, tuned separately for light and dark so contrast stays right in both.
enum Palette {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

    static let canvas   = adaptive(light: rgb(244, 244, 247), dark: rgb(24, 24, 27))
    static let card     = adaptive(light: .white, dark: rgb(36, 36, 40))
    static let well     = adaptive(light: NSColor(white: 0, alpha: 0.055), dark: NSColor(white: 1, alpha: 0.07))
    static let hairline = adaptive(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.08))

    static let accent    = adaptive(light: rgb(99, 82, 238), dark: rgb(150, 136, 255))
    static let accent2   = adaptive(light: rgb(52, 120, 246), dark: rgb(96, 160, 255))
    static let attention = adaptive(light: rgb(232, 110, 18), dark: rgb(255, 159, 67))
    static let ready     = adaptive(light: rgb(22, 156, 98), dark: rgb(64, 208, 140))
    static let muted     = adaptive(light: rgb(142, 142, 150), dark: rgb(120, 120, 128))
}

enum Metrics {
    static let width: CGFloat = 384
    static let gutter: CGFloat = 14
    static let cardRadius: CGFloat = 14
    static let maxListHeight: CGFloat = 540
    static let icon: CGFloat = 28
    static let iconGap: CGFloat = 11
}

extension SessionStatus {
    var tint: Color {
        switch self {
        case .working: Palette.accent
        case .needsInput: Palette.attention
        case .idle: Palette.ready
        case .stopped: Palette.muted
        }
    }
    var symbol: String {
        switch self {
        case .working: "sparkles"
        case .needsInput: "hand.raised.fill"
        case .idle: "checkmark"
        case .stopped: "flag.checkered"
        }
    }
    var sectionTitle: String {
        switch self {
        case .needsInput: "Needs you"
        case .working: "In progress"
        case .idle: "Ready for more"
        case .stopped: "Finished"
        }
    }
}

// MARK: - Popover

struct PopoverView: View {
    @EnvironmentObject var store: SessionStore
    @State private var filter: Filter = .active
    @State private var listHeight: CGFloat = 0
    @State private var spin = 0.0

    enum Filter: String, CaseIterable, Identifiable {
        case active = "Now", recent = "All"
        var id: Self { self }
    }

    private var nowSessions: [CopilotSession] { store.sessions.filter { $0.isActive || $0.status == .idle } }
    private var shown: [CopilotSession] { filter == .active ? nowSessions : store.sessions }

    private var sections: [(status: SessionStatus, items: [CopilotSession])] {
        [SessionStatus.needsInput, .working, .idle, .stopped].compactMap { s in
            let items = shown.filter { $0.status == s }
            return items.isEmpty ? nil : (s, items)
        }
    }

    private var overallTint: Color {
        if store.needsInputCount > 0 { return Palette.attention }
        if store.activeCount > 0 { return Palette.accent }
        if store.sessions.contains(where: { $0.status == .idle }) { return Palette.ready }
        return Palette.muted
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if shown.isEmpty { emptyState } else { list }
            footer
        }
        .frame(width: Metrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(backdrop)
        .animation(.snappy(duration: 0.28), value: filter)
        .onAppear { store.doneAt = nil }
    }

    private var backdrop: some View {
        ZStack(alignment: .top) {
            Palette.canvas
            LinearGradient(colors: [overallTint.opacity(0.13), overallTint.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .animation(.easeInOut(duration: 0.6), value: store.needsInputCount)
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            AppGlyph(alert: store.needsInputCount > 0)
            VStack(alignment: .leading, spacing: 1) {
                Text("Copilot")
                    .font(.system(size: 14, weight: .semibold))
                    .help("Each item is one conversation (a “session”) you've had with GitHub Copilot.")
                Text(summaryLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            FilterControl(selection: $filter, counts: [.active: nowSessions.count, .recent: store.sessions.count])
                .help("Now: work in progress or waiting for you. All: everything, including finished work.")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var summaryLine: String {
        let n = store.needsInputCount, a = store.activeCount
        if n > 0 { return n == 1 ? "1 needs your answer" : "\(n) need your answer" }
        if a > 0 { return a == 1 ? "Working on 1 thing" : "Working on \(a) things" }
        if store.sessions.contains(where: { $0.status == .idle }) { return "All quiet · Ready for your next request" }
        return "Nothing running right now"
    }

    // MARK: List

    private var list: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections, id: \.status) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(status: section.status, count: section.items.count)
                        ForEach(section.items) { SessionCard(session: $0) }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 2)
            .padding(.bottom, Metrics.gutter)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { listHeight = $0 }
        }
        .scrollIndicators(.automatic)
        .frame(height: min(max(listHeight, 120), Metrics.maxListHeight))
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 6)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
            }
        }
    }

    private var emptyState: some View {
        let isNow = filter == .active
        return VStack(spacing: 10) {
            ZStack {
                Circle().fill(Palette.accent.opacity(0.07)).frame(width: 72, height: 72)
                Circle().fill(Palette.accent.opacity(0.12)).frame(width: 48, height: 48)
                Image(systemName: isNow ? "moon.stars.fill" : "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.bottom, 4)
            Text(isNow ? "Nothing in progress" : "No Copilot work yet")
                .font(.system(size: 13, weight: .semibold))
            Text(isNow
                 ? "When you ask Copilot to do something, it shows up here."
                 : "Open GitHub Copilot and start a chat. It will appear here automatically.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
            if isNow && !store.sessions.isEmpty {
                Button { filter = .recent } label: { Text("See earlier work") }
                    .buttonStyle(PillButtonStyle(tint: Palette.accent, filled: false))
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 34)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Button { SessionActions.openCopilot() } label: {
                HStack(spacing: 5) {
                    Text("Open GitHub Copilot")
                    Image(systemName: "arrow.up.right").font(.system(size: 8.5, weight: .bold))
                }
            }
            .buttonStyle(FooterLinkStyle())
            .help("Opens the Copilot app so you can chat with it")

            Spacer()

            LiveIndicator().padding(.trailing, 6)

            IconButton(symbol: "arrow.clockwise", help: "Check for the latest updates", rotation: spin) {
                withAnimation(.easeInOut(duration: 0.6)) { spin += 360 }
                store.refresh()
            }
            IconButton(symbol: "power", help: "Close this helper (Copilot itself keeps running)", shortcut: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: 40)
        .background(Palette.well.opacity(0.5))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

// MARK: - Session card

struct SessionCard: View {
    let session: CopilotSession
    @State private var expanded = false
    @State private var hovering = false

    private var tint: Color { session.status.tint }
    private var needsYou: Bool { session.status == .needsInput }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.iconGap) {
            StatusIcon(status: session.status)
            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                if let q = session.question { QuestionCallout(text: q, tint: tint) }
                progress
                if session.question == nil, let m = session.lastMessage, session.status != .working || session.todos.isEmpty {
                    Text(m)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if expanded && !session.todos.isEmpty {
                    StepList(todos: session.todos, tint: tint)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                actions.padding(.top, 2)
            }
        }
        .padding(13)
        .background(cardBackground)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        return shape
            .fill(Palette.card)
            .overlay(shape.strokeBorder(needsYou ? tint.opacity(0.55) : Palette.hairline, lineWidth: 1))
            .shadow(color: needsYou ? tint.opacity(0.18) : .black.opacity(hovering ? 0.10 : 0.045),
                    radius: hovering ? 10 : 4, y: hovering ? 4 : 1)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(session.status == .stopped ? .secondary : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(session.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 5) {
                Image(systemName: "folder").font(.system(size: 9.5, weight: .medium))
                Text(session.repoShortName).lineLimit(1)
                    .help("The project Copilot is working in")
                if let b = session.branch {
                    Text("·").foregroundStyle(.quaternary)
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9.5, weight: .medium))
                    Text(b)
                        .font(.system(size: 10.5, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .help("Your own copy of the project to experiment in (called a “branch”). Your changes don't affect the main version until they're reviewed.")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            (Text(session.status.label).foregroundStyle(tint).fontWeight(.semibold)
             + Text("  ·  ").foregroundStyle(.quaternary)
             + Text(nextStep).foregroundStyle(.tertiary))
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
    }

    private var nextStep: String {
        switch session.status {
        case .needsInput: "Open Copilot to answer."
        case .working: "You can keep working while it finishes."
        case .idle: "Give it the next task in Copilot."
        case .stopped: "Start a new chat in Copilot to continue."
        }
    }

    @ViewBuilder private var progress: some View {
        if let p = session.progress {
            VStack(alignment: .leading, spacing: 7) {
                ProgressTrack(value: p, tint: tint)
                HStack(spacing: 8) {
                    Text(session.status == .working
                         ? (session.currentTodo?.title ?? session.activity)
                         : "\(session.doneCount) of \(session.todos.count) steps done")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                        HStack(spacing: 4) {
                            Text("Steps").fontWeight(.medium)
                            Text("\(session.doneCount)/\(session.todos.count)").monospacedDigit().foregroundStyle(.tertiary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5, weight: .bold))
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                        .padding(.horizontal, 7).frame(height: 20)
                        .background(Capsule().fill(Palette.well.opacity(hovering ? 1 : 0.6)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Copilot's to-do list for this task")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        } else if session.status == .working {
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(session.activity).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button { SessionActions.openCopilot() } label: {
                HStack(spacing: 5) {
                    Image(systemName: needsYou ? "arrowshape.turn.up.left.fill" : "arrow.up.forward")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(needsYou ? "Answer in Copilot" : "Open in Copilot")
                }
            }
            .buttonStyle(PillButtonStyle(tint: needsYou ? tint : Palette.accent, filled: needsYou))
            .help("Open the Copilot app")

            Spacer(minLength: 0)

            Group {
                IconButton(symbol: "folder", help: "Show project files in Finder") { SessionActions.showInFinder(session) }
                IconButton(symbol: "chevron.left.forwardslash.chevron.right", help: "Open in code editor") { SessionActions.openInEditor(session) }
                MoreMenu(session: session)
            }
            .opacity(hovering ? 1 : 0.6)
        }
    }
}

// MARK: - Components

/// The app's mark: a soft gradient tile with a sparkle, with a small dot when something needs you.
struct AppGlyph: View {
    let alert: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(colors: [Palette.accent, Palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .overlay(Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
            .frame(width: 32, height: 32)
            .shadow(color: Palette.accent.opacity(0.35), radius: 6, y: 2)
            .overlay(alignment: .topTrailing) {
                if alert {
                    Circle().fill(Palette.attention)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Palette.canvas, lineWidth: 2))
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }
}

struct FilterControl: View {
    @Binding var selection: PopoverView.Filter
    let counts: [PopoverView.Filter: Int]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PopoverView.Filter.allCases) { f in
                let on = f == selection
                Button { selection = f } label: {
                    HStack(spacing: 4) {
                        Text(f.rawValue)
                        if let c = counts[f], c > 0 {
                            Text("\(c)").monospacedDigit().foregroundStyle(on ? .secondary : .tertiary)
                        }
                    }
                    .font(.system(size: 11, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background {
                        if on {
                            Capsule().fill(Palette.card)
                                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                                .matchedGeometryEffect(id: "selection", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.well))
    }
}

struct SectionHeader: View {
    let status: SessionStatus
    let count: Int
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(status.tint).frame(width: 5, height: 5)
            Text(status.sectionTitle.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.leading, 3)
    }
}

/// Tinted circle with the status symbol; animated while Copilot works or waits for you.
struct StatusIcon: View {
    let status: SessionStatus
    var body: some View {
        ZStack {
            if status == .needsInput { PulseRing(tint: status.tint) }
            Circle().fill(status.tint.opacity(0.14))
            Image(systemName: status.symbol)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(status.tint)
            if status == .working { SpinningArc(tint: status.tint) }
        }
        .frame(width: Metrics.icon, height: Metrics.icon)
    }
}

struct SpinningArc: View {
    let tint: Color
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360))
        }
    }
}

struct PulseRing: View {
    let tint: Color
    var body: some View {
        TimelineView(.animation) { ctx in
            let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
            Circle()
                .stroke(tint.opacity(0.5 * (1 - phase)), lineWidth: 1.5)
                .scaleEffect(1 + phase * 0.5)
        }
    }
}

struct QuestionCallout: View {
    let text: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COPILOT ASKS")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .padding(.leading, 15)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.09)))
        .overlay(alignment: .leading) {
            Capsule().fill(tint).frame(width: 3).padding(.vertical, 9).padding(.leading, 6)
        }
    }
}

struct ProgressTrack: View {
    let value: Double
    let tint: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, g.size.width * value))
            }
        }
        .frame(height: 5)
        .animation(.spring(duration: 0.5), value: value)
    }
}

/// Copilot's to-do list, drawn as a small vertical timeline.
struct StepList: View {
    let todos: [TodoItem]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(todos.enumerated()), id: \.element.id) { i, t in
                HStack(alignment: .top, spacing: 9) {
                    VStack(spacing: 2) {
                        StepMarker(state: t.state, tint: tint).frame(width: 14, height: 14)
                        if i < todos.count - 1 {
                            Rectangle().fill(Palette.hairline).frame(width: 1).frame(maxHeight: .infinity)
                        }
                    }
                    Text(t.title)
                        .font(.system(size: 11.5, weight: t.state == .in_progress ? .medium : .regular))
                        .foregroundStyle(t.state == .done ? .tertiary : .primary)
                        .strikethrough(t.state == .done, color: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, i < todos.count - 1 ? 8 : 0)
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.well.opacity(0.55)))
    }
}

struct StepMarker: View {
    let state: TodoItem.State
    let tint: Color
    var body: some View {
        switch state {
        case .done:
            Circle().fill(Palette.ready)
                .overlay(Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white))
        case .in_progress:
            Circle().strokeBorder(tint, lineWidth: 1.5)
                .overlay(Circle().fill(tint).padding(3.5))
        case .blocked:
            Circle().fill(Palette.attention)
                .overlay(Image(systemName: "exclamationmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white))
        case .pending:
            Circle().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1.2)
        }
    }
}

struct LiveIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Palette.ready).frame(width: 6, height: 6)
                .background(Circle().fill(Palette.ready.opacity(0.25)).frame(width: 10, height: 10))
            Text("Live").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.tertiary)
        }
        .help("Updates automatically every few seconds")
    }
}

struct MoreMenu: View {
    let session: CopilotSession
    @State private var hover = false
    var body: some View {
        Menu {
            Button { SessionActions.showInFinder(session) } label: { Label("Show project files in Finder", systemImage: "folder") }
            Button { SessionActions.openInEditor(session) } label: { Label("Open in code editor", systemImage: "chevron.left.forwardslash.chevron.right") }
            if session.repository != nil {
                Divider()
                Button { SessionActions.openBranch(session) } label: { Label("See my version on GitHub", systemImage: "arrow.triangle.branch") }
                Button { SessionActions.openPullRequests(session) } label: { Label("See review requests on GitHub", systemImage: "arrow.triangle.pull") }
            }
            Divider()
            Button { SessionActions.copyID(session) } label: { Label("Copy session ID (for support)", systemImage: "doc.on.doc") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 11.5, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 26)
        .background(Circle().fill(Palette.well.opacity(hover ? 1 : 0)))
        .contentShape(Circle())
        .onHover { hover = $0 }
        .help("Other places you can jump to from this session")
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var rotation: Double = 0
    var shortcut: KeyEquivalent? = nil
    let action: () -> Void
    @State private var hover = false

    init(symbol: String, help: String, rotation: Double = 0, shortcut: KeyEquivalent? = nil, action: @escaping () -> Void) {
        self.symbol = symbol; self.help = help; self.rotation = rotation; self.shortcut = shortcut; self.action = action
    }

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .rotationEffect(.degrees(rotation))
                .foregroundStyle(hover ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Palette.well.opacity(hover ? 1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }

        if let shortcut { button.keyboardShortcut(shortcut) } else { button }
    }
}

struct PillButtonStyle: ButtonStyle {
    let tint: Color
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, tint: tint, filled: filled)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let tint: Color
        let filled: Bool
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(filled ? Color.white : tint)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background {
                    if filled {
                        Capsule().fill(tint.gradient)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: tint.opacity(0.35), radius: hover ? 6 : 3, y: 1)
                    } else {
                        Capsule().fill(tint.opacity(hover ? 0.17 : 0.1))
                    }
                }
                .brightness(filled && hover ? 0.04 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .contentShape(Capsule())
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

struct FooterLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { LinkBody(configuration: configuration) }

    private struct LinkBody: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hover ? Palette.accent : Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Capsule().fill(Palette.well.opacity(hover ? 1 : 0)))
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
        }
    }
}
