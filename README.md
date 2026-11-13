# PajlotAssist

A menu bar and Dock companion for GitHub Copilot, made for designers. Shows your Copilot sessions, their status and step progress, and offers quick actions (open Copilot, folder, editor, branch, PRs).

On first launch a welcome screen lets you choose where it lives: the Dock (opens as a window), the menu bar, or both. Change it later in Settings (⌘, or the gear in the popover). There's also a desktop widget (small, medium, large): right-click the desktop → Edit Widgets → Pajlot Assist. The app keeps the widget up to date through a shared App Group, so the app needs to be running.

Reads `~/.copilot` read-only. Build with `./Scripts/build-app.sh` or the Xcode project (macOS 15+, signed with the RD223D229Z team; `swift build` still works but has no widget); the app lands in `build/PajlotAssist.app`.
