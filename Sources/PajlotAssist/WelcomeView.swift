import SwiftUI
import AppKit

/// The splash screen shown on first launch: what the app does, where it should live, and the widget.
struct WelcomeView: View {
    static let windowID = "welcome"

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Prefs.dock) private var dock = true
    @AppStorage(Prefs.menuBar) private var menuBar = true
    @AppStorage(Prefs.welcome) private var hasSeenWelcome = false

    var body: some View {
        VStack(spacing: 0) {
            hero
                .padding(.top, 34).padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 22) {
                block(number: 1, title: "Where should it live?") { PlacementPicker() }
                block(number: 2, title: "Add it to your desktop, too") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pajlot Assist comes with a widget, so you can keep an eye on your sessions without opening anything.")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        WidgetShowcase()
                    }
                }
            }
            .padding(.horizontal, 28)

            footer
                .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 24)
        }
        .frame(width: 600)
        .background(Palette.canvas)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 76, height: 76)
                .shadow(color: Palette.accent.opacity(0.25), radius: 14, y: 6)
            Text("Welcome to Pajlot Assist")
                .font(.system(size: 22, weight: .bold))
            Text("Keep an eye on your Copilot sessions: what's working, what's done,\nand what's waiting for you.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func block<C: View>(number: Int, title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(Circle().fill(Palette.accent))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            content()
        }
    }

    private var footer: some View {
        HStack {
            Text(whereToFind).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer()
            Button("Get started", action: finish)
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var whereToFind: String {
        switch (dock, menuBar) {
        case (true, true): "You'll find it in the Dock and at the top of your screen."
        case (true, false): "You'll find it in the Dock."
        default: "You'll find it at the top right of your screen."
        }
    }

    private func finish() {
        hasSeenWelcome = true
        if dock { openWindow(id: MainWindow.id) }
        dismissWindow(id: Self.windowID)
        NSApp.activate()
    }
}
