import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [CopilotSession] = []
    @Published private(set) var lastRefresh = Date()
    /// Set when a session goes from working to finished; drives the "done" icon until seen.
    @Published var doneAt: Date?

    private let home: String
    private var timer: Timer?
    private var watcher: FolderWatcher?
    /// Per-session results, reused until the underlying file changes.
    struct CachedSession {
        var stamp = "", snap = EventSnapshot()
        var todoStamp = "", todos: [TodoItem] = []
    }
    private var cache: [String: CachedSession] = [:]
    /// Sessions found on disk (not only in Copilot's database, which can lag or miss new sessions).
    private var diskIDs: Set<String> = []
    private var loading = false
    private var refreshAgain = false
    private var ticks = 0

    var activeCount: Int { sessions.filter(\.isActive).count }
    var needsInputCount: Int { sessions.filter { $0.status == .needsInput }.count }

    /// `home` is only overridden by tests; the app always reads the user's own ~/.copilot.
    init(home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.home = home
        refresh(scan: true)
        // React to Copilot writing to a session within a fraction of a second.
        watcher = FolderWatcher(path: home + "/.copilot/session-state", latency: 0.25) { [weak self] paths in
            MainActor.assumeIsolated { self?.filesChanged(paths) }
        }
        // Fallback tick: keeps "x min ago" fresh and catches anything the watcher misses.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.ticks += 1
                self.refresh(scan: self.ticks % 20 == 0)
            }
        }
    }

    /// Static store for previews and snapshots; never touches Copilot's data.
    init(preview: [CopilotSession]) { home = ""; sessions = preview }

    private func filesChanged(_ paths: [String]) {
        // FSEvents reports real paths (e.g. /private/var/…), so match against the resolved folder too.
        let plain = home + "/.copilot/session-state/"
        let roots = [plain, (realpath(plain, nil).map { String(cString: $0) } ?? plain) + "/"]
        for p in paths {
            guard let root = roots.first(where: { p.hasPrefix($0) }),
                  let id = p.dropFirst(root.count).split(separator: "/").first, id.count >= 32 else { continue }
            diskIDs.insert(String(id))
        }
        refresh()
    }

    /// Reloads all sessions off the main thread. Calls that arrive mid-load are coalesced into one follow-up.
    func refresh(scan: Bool = false) {
        if loading { refreshAgain = true; return }
        loading = true
        let home = home
        let cached = cache
        let known = diskIDs
        Task.detached(priority: .userInitiated) {
            let found = scan ? Self.scanRecent(home: home) : []
            let (result, newCache) = Self.load(home: home, cache: cached, extraIDs: known.union(found))
            await MainActor.run {
                self.diskIDs.formUnion(found)
                self.cache = newCache
                let before = Dictionary(uniqueKeysWithValues: self.sessions.map { ($0.id, $0.status) })
                if result.contains(where: { before[$0.id] == .working && ($0.status == .idle || $0.status == .stopped) }) { self.doneAt = Date() }
                self.sessions = result
                self.publishToWidget()
                self.lastRefresh = Date()
                self.loading = false
                if self.refreshAgain { self.refreshAgain = false; self.refresh() }
            }
        }
    }

    // MARK: - Widget

    private var lastWidgetSessions: [WidgetSnapshot.Session]?

    /// Hands the desktop widget a fresh summary, but only reloads it when something it shows changed.
    private func publishToWidget() {
        let items = sessions.filter { $0.status != .stopped }.prefix(8).map {
            WidgetSnapshot.Session(id: $0.id, title: $0.title, repo: $0.repoShortName, status: $0.status.rawValue,
                                   activity: $0.activity, question: $0.question,
                                   done: $0.doneCount, total: $0.todos.count, updatedAt: $0.updatedAt)
        }
        guard items != lastWidgetSessions else { return }
        lastWidgetSessions = items
        if WidgetSnapshot(sessions: Array(items), savedAt: Date()).save() {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
        }
    }

    // MARK: - Loading (off the main thread)

    /// Session folders whose event log changed in the last 30 days.
    nonisolated private static func scanRecent(home: String) -> Set<String> {
        let dir = home + "/.copilot/session-state"
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return Set(names.filter { name in
            let m = (try? fm.attributesOfItem(atPath: dir + "/" + name + "/events.jsonl"))?[.modificationDate] as? Date
            return (m ?? .distantPast) > cutoff
        })
    }

    /// Minimal reader for the flat `key: value` lines in a session's workspace.yaml.
    nonisolated private static func workspace(dir: String) -> [String: String] {
        guard let text = try? String(contentsOfFile: dir + "/workspace.yaml", encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix(" ") {
            guard let i = line.firstIndex(of: ":") else { continue }
            var v = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            if v.count >= 2, v.first == v.last, v.first == "\"" || v.first == "'" { v = String(v.dropFirst().dropLast()) }
            out[String(line[..<i])] = v
        }
        return out
    }

    nonisolated private static func load(home: String, cache: [String: CachedSession], extraIDs: Set<String>)
        -> ([CopilotSession], [String: CachedSession]) {
        let root = home + "/.copilot"
        let rows = SQLiteReader.rows(path: root + "/session-store.db", sql: """
            SELECT id, cwd, repository, branch, summary, updated_at FROM sessions
            WHERE updated_at > datetime('now','-30 day') ORDER BY updated_at DESC LIMIT 60
            """)
        let sqlDate = ISO8601DateFormatter()
        sqlDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = DateFormatter(); plain.dateFormat = "yyyy-MM-dd HH:mm:ss"; plain.timeZone = TimeZone(identifier: "UTC")

        var newCache: [String: CachedSession] = [:]
        var out: [CopilotSession] = []
        let fm = FileManager.default

        // Sessions Copilot hasn't put in its database yet: take their details from workspace.yaml.
        let inDB = Set(rows.compactMap { $0["id"] })
        var all = rows
        for id in extraIDs.subtracting(inDB) {
            let w = workspace(dir: root + "/session-state/" + id)
            guard !w.isEmpty else { continue }
            all.append(["id": id, "cwd": w["cwd"] ?? "", "repository": w["repository"] ?? "", "branch": w["branch"] ?? "",
                        "summary": w["name"] ?? w["summary"] ?? "", "updated_at": w["updated_at"] ?? ""])
        }

        for r in all {
            guard let id = r["id"] else { continue }
            let dir = root + "/session-state/" + id
            guard fm.fileExists(atPath: dir) else { continue }

            let attrs = try? fm.attributesOfItem(atPath: dir + "/events.jsonl")
            let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let stamp = "\(mtime.timeIntervalSince1970)-\(size)"
            var entry = cache[id] ?? CachedSession()
            if entry.stamp != stamp { entry.stamp = stamp; entry.snap = EventTail.read(sessionDir: dir) }
            let snap = entry.snap
            let todoStamp = fileStamp(dir + "/session.db") + "|" + fileStamp(dir + "/session.db-wal")
            if entry.todoStamp != todoStamp { entry.todoStamp = todoStamp; entry.todos = readTodos(dir: dir) }
            newCache[id] = entry

            let live = isLive(dir: dir)
            let last = max(snap.lastEvent ?? .distantPast, mtime)
            let age = Date().timeIntervalSince(last)

            let status: SessionStatus
            if snap.pendingQuestion != nil && !snap.shutDown && (live || age < 3600) { status = .needsInput }
            else if snap.turnOpen && !snap.shutDown && (live ? age < 900 : age < 120) { status = .working }
            else if live { status = .idle }
            else { status = .stopped }

            let todos = entry.todos
            var title = (r["summary"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { title = (workspace(dir: dir)["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            let updated = (r["updated_at"]).flatMap { sqlDate.date(from: $0) ?? plain.date(from: $0) } ?? last

            out.append(CopilotSession(
                id: id,
                title: title.isEmpty ? "Untitled session" : title,
                cwd: r["cwd"] ?? "",
                repository: r["repository"].flatMap { $0.isEmpty ? nil : $0 },
                branch: r["branch"].flatMap { $0.isEmpty ? nil : $0 },
                updatedAt: max(updated, last),
                status: status,
                activity: status == .working ? EventTail.friendly(tool: snap.pendingTool) : status.label,
                lastMessage: snap.lastMessage.map(clean),
                question: snap.pendingQuestion.map(clean),
                todos: todos))
        }
        out.sort { ($0.status.sortRank, $1.updatedAt) < ($1.status.sortRank, $0.updatedAt) }
        return (out, newCache)
    }

    nonisolated private static func isLive(dir: String) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return false }
        for f in files where f.hasPrefix("inuse.") && f.hasSuffix(".lock") {
            let parts = f.split(separator: ".")
            if parts.count == 3, let pid = Int32(parts[1]), kill(pid, 0) == 0 { return true }
        }
        return false
    }

    nonisolated private static func fileStamp(_ path: String) -> String {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path) else { return "-" }
        return "\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)-\((a[.size] as? NSNumber)?.intValue ?? 0)"
    }

    nonisolated private static func readTodos(dir: String) -> [TodoItem] {
        let path = dir + "/session.db"
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        return SQLiteReader.rows(path: path, sql: "SELECT id, title, description, status FROM todos ORDER BY created_at, rowid").compactMap {
            guard let id = $0["id"], let t = $0["title"] else { return nil }
            return TodoItem(id: id, title: t, detail: $0["description"] ?? "", state: TodoItem.State(rawValue: $0["status"] ?? "") ?? .pending)
        }
    }

    nonisolated private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Watches a folder tree with FSEvents and reports the changed paths on the main queue.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void

    init?(path: String, latency: TimeInterval, handler: @escaping ([String]) -> Void) {
        self.handler = handler
        var ctx = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        ctx.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            me.handler(unsafeBitCast(paths, to: NSArray.self) as? [String] ?? [])
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, callback, &ctx, [path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return nil }
        stream = s
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
    }

    deinit {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
    }
}
