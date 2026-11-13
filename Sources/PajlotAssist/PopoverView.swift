import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var store: SessionStore
    @State private var filter: Filter = .active
    enum Filter: String, CaseIterable { case active = "Now", recent = "All" }

    private var shown: [CopilotSession] {
        switch filter {
        case .active: store.sessions.filter { $0.isActive || $0.status == .idle }
        case .recent: store.sessions
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if shown.isEmpty { empty } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(shown) { SessionCard(session: $0) }
                    }.padding(12)
                }
                .frame(height: min(520, max(180, CGFloat(shown.count) * 175)))
            }
            Divider()
            footer
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.doneAt = nil }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Your Copilot work").font(.headline)
                    .help("Each item is one conversation (a “session”) you've had with GitHub Copilot.")
                Text(summaryLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 110)
            .help("Now: work in progress or waiting for you. All: everything, including finished work.")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var summaryLine: String {
        let n = store.needsInputCount, a = store.activeCount
        if n > 0 { return n == 1 ? "1 needs your answer" : "\(n) need your answer" }
        if a > 0 { return a == 1 ? "Copilot is working on 1 thing" : "Copilot is working on \(a) things" }
        let idle = store.sessions.filter { $0.status == .idle }.count
        if idle > 0 { return "All quiet · Copilot is ready for your next request" }
        return "Nothing running right now"
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz").font(.title).foregroundStyle(.secondary)
            Text(filter == .active ? "Nothing in progress" : "No Copilot work found yet").font(.subheadline)
            Text(filter == .active
                 ? "When you ask Copilot to do something, it shows up here. Tap “All” to see earlier work."
                 : "Open GitHub Copilot and start a chat. It will appear here automatically.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
    }

    private var footer: some View {
        HStack {
            Button { SessionActions.openCopilot() } label: { Label("Open GitHub Copilot", systemImage: "arrow.up.forward.app") }
                .help("Opens the Copilot app so you can chat with it")
            Spacer()
            Button("Refresh") { store.refresh() }.help("Check for the latest updates")
            Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                .help("Close this helper (Copilot itself keeps running)")
        }
        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

struct SessionCard: View {
    let session: CopilotSession
    @State private var expanded = false

    private var tint: Color {
        switch session.status {
        case .working: .blue
        case .needsInput: .orange
        case .idle: .green
        case .stopped: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusDot(color: tint, pulsing: session.status == .working)
                Text(session.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 4)
                Text(session.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "folder").font(.caption2)
                Text(session.repoShortName).help("The project Copilot is working in")
                if let b = session.branch {
                    Image(systemName: "arrow.triangle.branch").font(.caption2)
                    Text(b).lineLimit(1)
                        .help("Your own copy of the project to experiment in (called a “branch”). Your changes don't affect the main version until they're reviewed.")
                }
            }.font(.caption).foregroundStyle(.secondary)

            Text("\(session.status.label) — \(nextStep)")
                .font(.caption2).foregroundStyle(session.status == .needsInput ? .orange : .secondary)

            if let q = session.question {
                Label { Text(q).lineLimit(3) } icon: { Image(systemName: "bubble.left.fill") }
                    .font(.caption).foregroundStyle(.orange)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            progress

            if session.question == nil, let m = session.lastMessage, session.status != .working || session.todos.isEmpty {
                Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }

            if expanded && !session.todos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.todos) { t in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: icon(t.state)).foregroundStyle(color(t.state)).font(.caption)
                            Text(t.title).font(.caption).strikethrough(t.state == .done).foregroundStyle(t.state == .done ? .secondary : .primary)
                        }
                    }
                }.padding(.top, 2)
            }

            actions
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(session.status == .needsInput ? Color.orange.opacity(0.6) : .clear, lineWidth: 1))
    }

    private var nextStep: String {
        switch session.status {
        case .needsInput: "Copilot asked you something. Open Copilot to answer."
        case .working: "You can keep working while it finishes."
        case .idle: "Done for now. Open Copilot to give it the next task."
        case .stopped: "This conversation has ended. Start a new one in Copilot."
        }
    }

    @ViewBuilder private var progress: some View {
        if let p = session.progress {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: p).tint(tint)
                HStack {
                    Text(session.status == .working ? (session.currentTodo?.title ?? session.activity) : "\(session.doneCount) of \(session.todos.count) steps done")
                        .lineLimit(1)
                    Spacer()
                    Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                        Text(expanded ? "Hide steps" : "Show steps (\(session.doneCount)/\(session.todos.count))")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }.buttonStyle(.plain).help("Copilot's to-do list for this task")
                }.font(.caption).foregroundStyle(.secondary)
            }
        } else if session.status == .working {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(session.activity).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button { SessionActions.openCopilot() } label: {
                Label(session.status == .needsInput ? "Answer in Copilot" : "Open Copilot", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .tint(session.status == .needsInput ? .orange : .accentColor)
            .help("Open the Copilot app")
            Spacer(minLength: 0)
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
            } label: { Label("More", systemImage: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Other places you can jump to from this session")
        }
    }

    private func icon(_ s: TodoItem.State) -> String {
        switch s { case .done: "checkmark.circle.fill"; case .in_progress: "circle.dotted"; case .blocked: "exclamationmark.circle.fill"; case .pending: "circle" }
    }
    private func color(_ s: TodoItem.State) -> Color {
        switch s { case .done: .green; case .in_progress: .blue; case .blocked: .orange; case .pending: .secondary }
    }
}

struct ActionButton: View {
    let title: String, symbol: String, prominent: Bool, action: () -> Void
    init(_ title: String, _ symbol: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.prominent = prominent; self.action = action
    }
    var body: some View {
        Button(action: action) { Image(systemName: symbol).frame(minWidth: 16) }
            .help(title)
            .buttonStyle(.bordered).controlSize(.small)
            .tint(prominent ? .orange : nil)
    }
}

struct StatusDot: View {
    let color: Color, pulsing: Bool
    @State private var on = false
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .opacity(pulsing && on ? 0.35 : 1)
            .onAppear { if pulsing { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { on = true } } }
    }
}
