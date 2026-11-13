import Foundation

/// Derives live state from the tail of a session's events.jsonl (files can be 100MB+, so we only read the end).
struct EventSnapshot {
    var turnOpen = false
    var shutDown = false
    var pendingTool: String?
    var pendingQuestion: String?
    var lastMessage: String?
    var lastEvent: Date?
}

enum EventTail {
    static let tailBytes = 600_000
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    static func read(sessionDir: String) -> EventSnapshot {
        var snap = EventSnapshot()
        guard let fh = FileHandle(forReadingAtPath: sessionDir + "/events.jsonl") else { return snap }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd() else { return snap }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // partial first line

        var open: [String: String] = [:]   // toolCallId -> toolName
        for line in lines {
            // Skip huge/noisy events cheaply before JSON parsing.
            if line.count > 200_000 { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            if let ts = obj["timestamp"] as? String, let d = iso.date(from: ts) { snap.lastEvent = d }
            let data = obj["data"] as? [String: Any] ?? [:]
            switch type {
            case "assistant.turn_start": snap.turnOpen = true; snap.shutDown = false
            case "assistant.turn_end": snap.turnOpen = false
            case "session.resume": snap.shutDown = false
            case "session.shutdown": snap.shutDown = true; snap.turnOpen = false; open.removeAll()
            case "abort": snap.turnOpen = false; open.removeAll()
            case "user.message": snap.turnOpen = true; snap.shutDown = false
            case "tool.execution_start":
                if let id = data["toolCallId"] as? String, let name = data["toolName"] as? String {
                    open[id] = name
                    if name == "ask_user" {
                        let args = data["arguments"] as? [String: Any]
                        snap.pendingQuestion = args?["question"] as? String
                    }
                }
            case "tool.execution_complete":
                if let id = data["toolCallId"] as? String {
                    if open[id] == "ask_user" { snap.pendingQuestion = nil }
                    open[id] = nil
                }
            case "human_response.recorded": snap.pendingQuestion = nil
            case "assistant.message":
                if let c = data["content"] as? String, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    snap.lastMessage = c
                }
            default: break
            }
        }
        if snap.pendingQuestion != nil, !open.values.contains("ask_user") { snap.pendingQuestion = nil }
        snap.pendingTool = open.values.first(where: { $0 != "ask_user" })
        return snap
    }

    /// Plain-language label for a tool, aimed at designers rather than engineers.
    static func friendly(tool: String?) -> String {
        switch tool {
        case "bash", "read_bash", "stop_bash": "Running a command"
        case "view", "glob", "rg": "Reading project files"
        case "apply_patch", "edit", "create": "Editing files"
        case "web_fetch", "web_search": "Looking something up online"
        case "open_canvas", "invoke_canvas_action", "list_canvas_capabilities": "Working in the preview"
        case "create_pull_request": "Opening a pull request"
        case "skill": "Loading a skill"
        case "sql", "session_store_sql": "Taking notes"
        case "publish_chat_update": "Posting an update"
        case .some(let t) where t.contains("figma"): "Working in Figma"
        case .some: "Working on it"
        case nil: "Thinking"
        }
    }
}
