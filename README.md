# DriveManager

A macOS tool to see what is using your disk space and clean up junk files safely. Built as a personal replacement for DaisyDisk.

What it will do:

- Scan a disk or folder and show it as a folder tree next to a sunburst chart, kept in sync.
- Give the disk a health score from 0 to 100 with a one-line note.
- Suggest what to clean (Xcode caches, old simulators, app caches, old backups, installers and more), each labelled Safe, Review or Careful.
- Move what you select to the Trash, with one-click undo.

Status: milestone 1, the scanner, is in progress. Try it:

```sh
swift run -c release drive-scan                # the whole disk (Macintosh HD)
swift run -c release drive-scan ~              # your home folder
swift build -c release && sudo .build/release/drive-scan   # include system folders
```

Give Terminal Full Disk Access first (System Settings > Privacy & Security > Full Disk Access), otherwise some folders read as empty. See `DriveManager.md` for the plan and decisions.

Requirements: macOS 26, Xcode 26.
