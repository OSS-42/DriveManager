# DriveManager

Native macOS app that replaces DaisyDisk for personal use: shows what uses disk space, scores the disk's health, suggests junk to clean, and cleans it safely.

## Decisions

- Personal use only. Maybe shared with friends as a zip; never the App Store, no paid Apple developer account, no notarisation.
- Target macOS 26 (owner runs 26.6.2). Swift + SwiftUI, AppKit where SwiftUI is too slow (large outline views).
- Design follows "prototype D": folder tree and sunburst kept in sync, a suggestions panel (Safe / Review / Careful), a Selected tray, then Move to Trash with undo.
- The app opens on a health score (0-100 plus one sentence). Suggestions are 30% of the score and each one shows the points it adds. Other parts: free space 40%, trend 15%, housekeeping 15%. Weights live in a settings file.

## Plan

Milestones, each ending in something runnable:

1. Fast scanner: command-line scan, timed against DaisyDisk; totals match Finder.
2. Explorer: tree + sunburst in sync, clickable path, Reveal in Finder, hidden space shown apart.
3. Safe delete: Selected tray, Move to Trash, undo log, protected folders.
4. Suggestions + health score: rules engine reading a JSON rules file.
5. Polish: scan cache, low-space alert, duplicate finder.

Planned layout: a Swift package with a `DriveCore` library (scanner, index, rules, cleaner) and a `drive-scan` CLI, then a SwiftUI app target that depends on `DriveCore`.

## Safety rules (non-negotiable)

- Never delete anything outside a temporary directory in tests.
- Everything except caches goes to the Trash (`FileManager.trashItem`), never `removeItem`, unless a rule explicitly says "delete".
- Never touch `/System`, `/usr`, `/bin`, `/private/var/vm`, or undownloaded iCloud placeholders.
- Photos Library, Documents, Desktop and Mail mailboxes can be browsed but never get suggestions.
- Sizes are allocated size on disk; count APFS clones and hard links once.

## Working in this repo

- `swift run -c release drive-scan ~` scans your home folder; `drive-scan --help` lists the options. Give your terminal Full Disk Access first, or some folders read as empty.
- `swift test` runs the tests.

- Code is written in a cloud Linux container, which has no Swift toolchain. CI (`.github/workflows/ci.yml`) builds and tests on a macOS runner; treat a green CI run as the build check.
- Keep `DriveCore` free of UI code so it can be unit-tested with `swift test`.
- Each cleanup rule gets a unit test against a fake folder tree.
