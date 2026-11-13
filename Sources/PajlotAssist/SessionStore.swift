import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [CopilotSession] = []
    @Published private(set) var lastRefresh = Date()
    /// Set when a session goes from working to finished; drives the "done" icon until seen.
    @Published var doneAt: Date?

    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private var timer: Timer?
    private var cache: [String: (stamp: String, snap: EventSnapshot)] = [:]

    var activeCount: Int { sessions.filter(\.isActive).count }
    var needsInputCount: Int { sessions.filter { $0.status == .needsInput }.count }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let home = home
        let cached = cache
        Task.detached(priority: .utility) {
            let (result, newCache) = Self.load(home: home, cache: cached)
            await MainActor.run {
                self.cache = newCache
                let before = Dictionary(uniqueKeysWithValues: self.sessions.map { ($0.id, $0.status) })
                if result.contains(where: { before[$0.id] == .working && ($0.status == .idle || $0.status == .stopped) }) { self.doneAt = Date() }
                self.sessions = result
                self.lastRefresh = Date()
                NSLog("PajlotAssist: loaded \(result.count) sessions")
            }
        }
    }

    // MARK: - Loading (off the main thread)

    nonisolated private static func load(home: String, cache: [String: (stamp: String, snap: EventSnapshot)])
        -> ([CopilotSession], [String: (stamp: String, snap: EventSnapshot)]) {
        let root = home + "/.copilot"
        let rows = SQLiteReader.rows(path: root + "/session-store.db", sql: """
            SELECT id, cwd, repository, branch, summary, updated_at FROM sessions
            WHERE updated_at > datetime('now','-30 day') ORDER BY updated_at DESC LIMIT 60
            """)
        let sqlDate = ISO8601DateFormatter()
        sqlDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = DateFormatter(); plain.dateFormat = "yyyy-MM-dd HH:mm:ss"; plain.timeZone = TimeZone(identifier: "UTC")

        var newCache: [String: (stamp: String, snap: EventSnapshot)] = [:]
        var out: [CopilotSession] = []
        let fm = FileManager.default

        for r in rows {
            guard let id = r["id"] else { continue }
            let dir = root + "/session-state/" + id
            guard fm.fileExists(atPath: dir) else { continue }

            let attrs = try? fm.attributesOfItem(atPath: dir + "/events.jsonl")
            let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let stamp = "\(mtime.timeIntervalSince1970)-\(size)"
            let snap: EventSnapshot
            if let c = cache[id], c.stamp == stamp { snap = c.snap } else { snap = EventTail.read(sessionDir: dir) }
            newCache[id] = (stamp, snap)

            let live = isLive(dir: dir)
            let last = max(snap.lastEvent ?? .distantPast, mtime)
            let age = Date().timeIntervalSince(last)

            let status: SessionStatus
            if snap.pendingQuestion != nil && !snap.shutDown && (live || age < 3600) { status = .needsInput }
            else if snap.turnOpen && !snap.shutDown && (live ? age < 900 : age < 120) { status = .working }
            else if live { status = .idle }
            else { status = .stopped }

            let todos = readTodos(dir: dir)
            let title = (r["summary"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
