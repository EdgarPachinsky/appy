# appy

Small dark macOS app (Flutter) that runs your local projects.

- Add project folders → Appy detects Flutter, Dart, Node (npm/yarn/pnpm/bun + framework), Rust, Go, Python, Swift, Docker Compose, Makefile and suggests run options.
- Card per project: run / stop, quick option chips, pin, rename, remove, custom commands.
- Flutter runs use `flutter run --machine`: **hot reload, hot restart, rebuild, quit**.
- Dev-server URLs (localhost:xxxx) are detected → one-click open.
- Menu bar icon: running apps first, then pinned projects — run, stop, reload, restart, rebuild straight from the dropdown.
- Live CPU / RAM per running command (whole process tree) on cards, output toolbar and menu bar.
- Search (⌘F) and tags → filter chips (All / Running / Pinned / #tag).
- Drag cards to reorder; drop folders on the window or the menu bar icon to add them.
- Ports panel on the dashboard: every listening port with its process / project, open in browser, kill (or type `4200` → Kill).
- Git branch + changed files / ahead / behind on every card.
- "Open in…" lists the editors, IDEs, terminals and git apps installed on your Mac that fit the project.
- Closing the window keeps Appy in the menu bar. Quitting stops everything it started.

## Setup

```bash
./setup.sh            # once: generates macos/, applies icon + entitlements, pub get
flutter run -d macos  # dev
flutter build macos   # release .app
```

Commands run with your login-shell environment (nvm, Homebrew, Flutter PATH…).

### Windows

Build on a Windows machine with Flutter and Visual Studio's "Desktop development with C++" workload:

```bash
flutter build windows   # → build\windows\x64\runner\Release\
```

Commands run through `cmd.exe`, and helper steps run through PowerShell. Not on Windows yet: notifications, dropping folders on the tray icon, "Run application" steps, and matching ports to projects by folder.
