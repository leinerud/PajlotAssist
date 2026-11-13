import Foundation

enum SessionStatus: String {
    case working, needsInput, idle, stopped

    var label: String {
        switch self {
        case .working: "Working"
        case .needsInput: "Needs you"
        case .idle: "Done"
        case .stopped: "Closed"
        }
    }
    var sortRank: Int {
        switch self {
        case .needsInput: 0
        case .working: 1
        case .idle: 2
        case .stopped: 3
        }
    }
}

struct TodoItem: Identifiable, Hashable {
    enum State: String { case pending, in_progress, done, blocked }
    let id: String
    let title: String
    let detail: String
    let state: State
}

struct CopilotSession: Identifiable, Hashable {
    let id: String
    var title: String
    var cwd: String
    var repository: String?
    var branch: String?
    var updatedAt: Date
    var status: SessionStatus
    var activity: String          // plain-language "what is it doing right now"
    var lastMessage: String?      // latest thing Copilot said
    var question: String?         // set when Copilot is waiting for an answer
    var todos: [TodoItem]

    var doneCount: Int { todos.filter { $0.state == .done }.count }
    var progress: Double? { todos.isEmpty ? nil : Double(doneCount) / Double(todos.count) }
    var currentTodo: TodoItem? { todos.first { $0.state == .in_progress } ?? todos.first { $0.state == .blocked } }
    var repoShortName: String { repository?.split(separator: "/").last.map(String.init) ?? URL(fileURLWithPath: cwd).lastPathComponent }
    var isActive: Bool { status == .working || status == .needsInput }
}
