import Foundation

/// What the app hands to the desktop widget. The widget is sandboxed and can't read ~/.copilot,
/// so the app writes this small summary into a shared App Group folder instead.
struct WidgetSnapshot: Codable, Equatable {
    struct Session: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let repo: String
        let status: String          // SessionStatus raw value
        let activity: String
        let question: String?
        let done: Int
        let total: Int
        let updatedAt: Date
    }
    var sessions: [Session] = []
    var savedAt = Date.distantPast

    static let appGroup = "RD223D229Z.se.humblebee.PajlotAssist"
    static let widgetKind = "PajlotSessions"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snap
    }

    /// Writes the snapshot; returns false when there is no shared folder (e.g. an unsigned SwiftPM build).
    @discardableResult
    func save() -> Bool {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
