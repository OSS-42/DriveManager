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

Planned layout: a Swift package with a `DriveCore` library (scanner, index, rules, cleaner) and a `drive-scan` CLI, and a SwiftUI app target `DriveManager` that depends on `DriveCore`. Pure logic the app needs (such as `SunburstLayout`) lives in `DriveCore` so it can be tested.

## Safety rules (non-negotiable)

- Never delete anything outside a temporary directory in tests.
- Everything except caches goes to the Trash (`FileManager.trashItem`), never `removeItem`, unless a rule explicitly says "delete".
- Never touch `/System`, `/usr`, `/bin`, `/private/var/vm`, or undownloaded iCloud placeholders.
- Photos Library, Documents, Desktop and Mail mailboxes can be browsed but never get suggestions.
- Sizes are allocated size on disk; count APFS clones and hard links once.

## Working in this repo

- `./scripts/make-app.sh` builds a universal `build/DriveManager.app` with its icon (from `Resources/AppIcon.png`, drawn in `Resources/AppIcon.svg`); `--install` copies it to /Applications, `--zip` makes a zip to share. It signs with the self-signed "DriveManager Local Signing" certificate when `scripts/make-signing-cert.sh` has created it (keeps Full Disk Access across rebuilds), otherwise ad-hoc. No developer account, no notarization. `swift run DriveManager` starts the app without a bundle for a quick look.
- `swift run -c release drive-scan` scans the whole startup disk and `drive-scan ~` your home folder; `sudo .build/release/drive-scan` also reads system folders; `drive-scan --help` lists the options. Give your terminal Full Disk Access first, or some folders read as empty.
- `swift test` runs the tests.
- Cleanup rules are built in (`Sources/DriveCore/DefaultRules.swift`). `~/Library/Application Support/DriveManager/rules.json` can add rules or replace one by id (paths take `*`, `?` and `**` for any depth; `exceptPaths` skips folders; `keepNewest` keeps the latest file of each type per folder; `explain` holds the what/why/how text of the "?" button); `settings.json` there holds `healthWeights` (`freeSpace`, `suggestions`, `trend`, `housekeeping`) and `disabledRules`; the Settings window (Cmd-comma) edits both.
- macOS files (installers, /Library/Updates, system caches and logs) use separate rules in `Sources/DriveCore/SystemRules.swift`, run only from the "Check macOS files" button, and never count toward the health score or "Clean all Safe items". Time Machine snapshots and simulator runtimes are listed with a Terminal command to copy, not moved to the Trash.
- "Automatic" cleaning means the one-click "Clean all Safe items" button, never a scheduled clean (Eric's call).

- Code is written in a cloud Linux container, which has no Swift toolchain. CI (`.github/workflows/ci.yml`) builds and tests on a macOS runner; treat a green CI run as the build check.
- Keep `DriveCore` free of UI code so it can be unit-tested with `swift test`.
- Each cleanup rule gets a unit test against a fake folder tree.
