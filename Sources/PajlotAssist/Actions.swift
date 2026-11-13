import AppKit

/// Safe, non-destructive actions. Nothing here writes to Copilot's data.
enum SessionActions {
    static func openCopilot() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.github.githubapp") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    static func showInFinder(_ s: CopilotSession) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: s.cwd)])
    }
    static func openInEditor(_ s: CopilotSession) {
        let dir = URL(fileURLWithPath: s.cwd)
        if let vsc = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            NSWorkspace.shared.open([dir], withApplicationAt: vsc, configuration: NSWorkspace.OpenConfiguration())
        } else { NSWorkspace.shared.open(dir) }
    }
    static func githubURL(_ s: CopilotSession, path: String) -> URL? {
        guard let repo = s.repository else { return nil }
        return URL(string: "https://github.com/\(repo)\(path)")
    }
    static func openBranch(_ s: CopilotSession) {
        guard let b = s.branch?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = githubURL(s, path: "/tree/\(b)") else { return }
        NSWorkspace.shared.open(url)
    }
    static func openPullRequests(_ s: CopilotSession) {
        guard let b = s.branch?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = githubURL(s, path: "/pulls?q=is%3Apr+head%3A\(b)") else { return }
        NSWorkspace.shared.open(url)
    }
    static func copyID(_ s: CopilotSession) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s.id, forType: .string)
    }
}
