import SwiftUI
import AppKit

/// Where the app shows up: the Dock, the menu bar, or both. At least one is always on.
enum Prefs {
    static let dock = "showInDock"
    static let menuBar = "showInMenuBar"
    static let welcome = "hasSeenWelcome"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [dock: true, menuBar: true])
    }
    static var showInDock: Bool { UserDefaults.standard.object(forKey: dock) as? Bool ?? true }
    static var hasSeenWelcome: Bool { UserDefaults.standard.bool(forKey: welcome) }

    /// Shows or hides the Dock icon right away, keeping our windows in front.
    @MainActor static func applyDockPolicy() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        DispatchQueue.main.async { NSApp.activate() }
    }
}

// MARK: - Dock / menu bar picker (used by the welcome screen and Settings)

struct PlacementPicker: View {
    @AppStorage(Prefs.dock) private var dock = true
    @AppStorage(Prefs.menuBar) private var menuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PlacementCard(kind: .dock, isOn: dock, locked: dock && !menuBar) {
                    dock.toggle()
                    Prefs.applyDockPolicy()
                }
                PlacementCard(kind: .menuBar, isOn: menuBar, locked: menuBar && !dock) {
                    menuBar.toggle()
                }
            }
            Text("Pick one or both. You can change this any time in Settings.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }
}

private struct PlacementCard: View {
    enum Kind {
        case dock, menuBar
        var title: String { self == .dock ? "In the Dock" : "In the menu bar" }
        var detail: String {
            self == .dock ? "Open it like any other app, in its own window."
                          : "One click away at the top of your screen, with a live status icon."
        }
    }
    let kind: Kind
    let isOn: Bool
    /// The last one switched on can't be switched off, or the app would be unreachable.
    let locked: Bool
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: { if !locked { withAnimation(.snappy(duration: 0.2)) { toggle() } } }) {
            VStack(alignment: .leading, spacing: 10) {
                illustration
                    .frame(height: 74)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.well))
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.title).font(.system(size: 13, weight: .semibold))
                        Text(kind.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isOn ? Palette.accent : Color.secondary.opacity(0.5))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(isOn ? Palette.accent : (hover ? Palette.muted.opacity(0.5) : Palette.hairline), lineWidth: isOn ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(locked ? "Keep at least one place on so you can reach Pajlot Assist" : "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// A tiny drawing of where the app will appear.
    @ViewBuilder private var illustration: some View {
        let tint = isOn ? Palette.accent : Palette.muted
        switch kind {
        case .dock:
            VStack {
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<4) { _ in RoundedRectangle(cornerRadius: 4).fill(Palette.muted.opacity(0.35)).frame(width: 16, height: 16) }
                    appGlyph(tint: tint).frame(width: 20, height: 20)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.card))
                .padding(.bottom, 8)
            }
        case .menuBar:
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Spacer()
                    ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 2).fill(Palette.muted.opacity(0.35)).frame(width: 10, height: 10) }
                    appGlyph(tint: tint).frame(width: 13, height: 13)
                    Text("9:41").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).frame(height: 20)
                .background(Palette.card)
                // The popover hanging from the icon.
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 6).fill(Palette.card)
                        .overlay(VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(tint.opacity(0.8)).frame(width: 34, height: 4)
                            Capsule().fill(Palette.muted.opacity(0.35)).frame(width: 48, height: 4)
                        }.padding(7), alignment: .topLeading)
                        .frame(width: 66, height: 40)
                        .padding(.trailing, 30).padding(.top, 5)
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func appGlyph(tint: Color) -> some View {
        Image(nsImage: NSApp.applicationIconImage).resizable()
            .saturation(isOn ? 1 : 0).opacity(isOn ? 1 : 0.6)
    }
}

// MARK: - Widget showcase

/// Static look-alikes of the desktop widget, plus how to add it.
struct WidgetShowcase: View {
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 8) {
                MockWidget(small: true).frame(width: 92, height: 92)
                MockWidget(small: false).frame(width: 196, height: 92)
            }
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Right-click your desktop")
                step(2, "Choose Edit Widgets…")
                step(3, "Search for Pajlot Assist")
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 7) {
            Text("\(n)").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
                .frame(width: 17, height: 17).background(Circle().fill(Palette.accent.opacity(0.14)))
            Text(text).font(.system(size: 12))
        }
    }
}

private struct MockWidget: View {
    let small: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "sparkles").font(.system(size: 7, weight: .bold)).foregroundStyle(Palette.accent)
                Text("Pajlot").font(.system(size: 7.5, weight: .semibold))
            }
            if small {
                Spacer(minLength: 0)
                Text("2").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Palette.attention)
                Text("need you").font(.system(size: 7.5, weight: .medium)).foregroundStyle(.secondary)
            } else {
                row("Redesign onboarding", "Needs you", Palette.attention)
                row("Fix dark mode colours", "Working", Palette.accent)
                row("Update README", "Done", Palette.ready)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.hairline))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func row(_ title: String, _ status: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(tint).frame(width: 2.5, height: 15)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 7.5, weight: .semibold)).lineLimit(1)
                Text(status).font(.system(size: 6.5)).foregroundStyle(tint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5).fill(Palette.card))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Where Pajlot Assist lives") { PlacementPicker() }
            section("Desktop widget") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("See your sessions right on the desktop, in a small, medium or large size. It updates while Pajlot Assist is running.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    WidgetShowcase()
                }
            }
            HStack {
                Spacer()
                Button("Show welcome screen again") {
                    openWindow(id: WelcomeView.windowID)
                    NSApp.activate()
                }
            }
        }
        .padding(22)
        .frame(width: 540)
        .background(Palette.canvas)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content()
        }
    }
}
