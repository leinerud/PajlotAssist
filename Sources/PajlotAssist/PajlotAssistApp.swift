import SwiftUI
import AppKit
import Combine

@main
struct PajlotAssistApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: SessionStore
    @StateObject private var animator = MenuBarIconAnimator()
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var mode: MenuBarIconMode {
        if store.needsInputCount > 0 { return .needsInput }
        if store.sessions.contains(where: { $0.status == .working }) { return .working }
        if store.doneAt != nil { return .done }
        return .idle
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: animator.image)
            if store.activeCount > 0 { Text("\(store.activeCount)") }
        }
        .onAppear { animator.set(mode) }
        .onChange(of: mode) { _, new in animator.set(new) }
        .onReceive(timer) { _ in
            if let d = store.doneAt, Date().timeIntervalSince(d) > 120 { store.doneAt = nil }
        }
    }
}
