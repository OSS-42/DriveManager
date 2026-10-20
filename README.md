# DriveManager

A macOS tool to see what is using your disk space and clean up junk files safely. Built as a personal replacement for DaisyDisk.

What it will do:

- Scan a disk or folder and show it as a folder tree next to a sunburst chart, kept in sync.
- Give the disk a health score from 0 to 100 with a one-line note.
- Suggest what to clean (Xcode caches, old simulators, app caches, old backups, installers and more), each labelled Safe, Review or Careful.
- Move what you select to the Trash, with one-click undo.

Status: planning done, milestone 1 (the scanner) is next. See `CLAUDE.md` for the plan and decisions.

Requirements: macOS 26, Xcode 26.
