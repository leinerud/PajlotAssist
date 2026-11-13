import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var store: SessionStore
    @State private var filter: Filter = .active
    enum Filter: String, CaseIterable { case active = "Active", recent = "Recent" }

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
        .onAppear { store.doneAt = nil }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Copilot sessions").font(.headline)
                Text(summaryLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 130)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var summaryLine: String {
        let n = store.needsInputCount, a = store.activeCount
        if n > 0 { return "\(n) waiting for you · \(a) active" }
        if a > 0 { return "\(a) working right now" }
        return "Nothing running"
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz").font(.title).foregroundStyle(.secondary)
            Text("No active sessions").font(.subheadline)
            Text("Switch to Recent to see earlier work.").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var footer: some View {
        HStack {
            Button { SessionActions.openCopilot() } label: { Label("Open GitHub Copilot", systemImage: "arrow.up.forward.app") }
            Spacer()
            Button("Refresh") { store.refresh() }
            Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
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
                Text(session.repoShortName)
                if let b = session.branch {
                    Image(systemName: "arrow.triangle.branch").font(.caption2)
                    Text(b).lineLimit(1)
                }
            }.font(.caption).foregroundStyle(.secondary)

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

    @ViewBuilder private var progress: some View {
        if let p = session.progress {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: p).tint(tint)
                HStack {
                    Text(session.status == .working ? (session.currentTodo?.title ?? session.activity) : "\(session.doneCount) of \(session.todos.count) steps done")
                        .lineLimit(1)
                    Spacer()
                    Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                        Text("\(session.doneCount)/\(session.todos.count)")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }.buttonStyle(.plain)
                }.font(.caption).foregroundStyle(.secondary)
            }
        } else if session.status == .working {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(session.activity).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ActionButton("Open Copilot", "arrow.up.forward.app", prominent: session.status == .needsInput) { SessionActions.openCopilot() }
            ActionButton("Folder", "folder") { SessionActions.showInFinder(session) }
            ActionButton("Editor", "chevron.left.forwardslash.chevron.right") { SessionActions.openInEditor(session) }
            if session.repository != nil {
                ActionButton("Branch", "arrow.triangle.branch") { SessionActions.openBranch(session) }
                ActionButton("PRs", "arrow.triangle.pull") { SessionActions.openPullRequests(session) }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Copy session ID") { SessionActions.copyID(session) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
