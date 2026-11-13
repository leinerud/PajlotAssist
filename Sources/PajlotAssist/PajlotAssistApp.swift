import SwiftUI
import AppKit
import Combine

@main
struct PajlotAssistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SessionStore()
    @AppStorage(Prefs.menuBar) private var showInMenuBar = true

    var body: some Scene {
        // The Dock window: the same view as the menu bar popover, in a regular window.
        // It opens at launch only for Dock users who are past the welcome screen.
        Window("Pajlot Assist", id: MainWindow.id) {
            PopoverView().environmentObject(store).registersWindowOpener()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .defaultLaunchBehavior(Prefs.hasSeenWelcome && Prefs.showInDock ? .presented : .suppressed)

        // First-launch splash: pick Dock and/or menu bar, and learn about the widget.
        Window("Welcome to Pajlot Assist", id: WelcomeView.windowID) {
            WelcomeView().registersWindowOpener()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .defaultLaunchBehavior(Prefs.hasSeenWelcome ? .suppressed : .presented)

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $showInMenuBar) {
            PopoverView().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

enum MainWindow {
    static let id = "main"
    /// Set by whichever SwiftUI view is alive, so AppKit callbacks (Dock clicks) can open the window.
    @MainActor static var open: (() -> Void)?
}

private struct WindowOpenerRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear {
            let open = openWindow
            MainWindow.open = { open(id: MainWindow.id); NSApp.activate() }
        }
    }
}

extension View {
    func registersWindowOpener() -> some View { modifier(WindowOpenerRegistration()) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        Prefs.applyDockPolicy()
    }
    /// Clicking the Dock icon (or the desktop widget) brings the window back if it was closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { MainActor.assumeIsolated { MainWindow.open?() } }
        return true
    }
    /// Closing the window keeps the app running (in the menu bar and/or Dock).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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
        .registersWindowOpener()
        .onChange(of: mode) { _, new in animator.set(new) }
        .onReceive(timer) { _ in
            if let d = store.doneAt, Date().timeIntervalSince(d) > 120 { store.doneAt = nil }
        }
    }
}
