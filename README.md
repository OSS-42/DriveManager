# DriveManager

A macOS tool to see what is using your disk space and clean up junk files safely. Built as a personal replacement for DaisyDisk.

What it will do:

- Scan a disk or folder and show it as a folder tree next to a sunburst chart, kept in sync.
- Give the disk a health score from 0 to 100 with a one-line note.
- Suggest what to clean (Xcode caches, old simulators, app caches, old backups, installers and more), each labelled Safe, Review or Careful.
- Move what you select to the Trash, with one-click undo.

Status: milestones 1 to 4 (scanner, explorer, safe delete, suggestions and health score) are done.

## Install

Once, create a local signing certificate so macOS keeps Full Disk Access after every rebuild (it asks for your password):

```sh
./scripts/make-signing-cert.sh
```

Then build and install into Applications, and open it from Launchpad or Spotlight:

```sh
./scripts/make-app.sh --install
```

Give DriveManager Full Disk Access (System Settings > Privacy & Security > Full Disk Access) so it can read every folder. After a `git pull`, run the same command again.

## Share with a friend

```sh
./scripts/make-app.sh --zip
```

This makes `build/DriveManager-<version>.zip`, which runs on Apple Silicon and Intel Macs with macOS 14 or later. It is not notarized by Apple, so the first time they open it macOS refuses: they go to System Settings > Privacy & Security, click "Open Anyway" next to DriveManager, and confirm. After that it opens normally.

## Command line

The command-line scanner from milestone 1 is still there:

```sh
swift run -c release drive-scan                # the whole disk (Macintosh HD)
swift run -c release drive-scan ~              # your home folder
swift build -c release && sudo .build/release/drive-scan   # include system folders
```

Give Terminal Full Disk Access first (System Settings > Privacy & Security > Full Disk Access), otherwise some folders read as empty. See `DriveManager.md` for the plan and decisions.

Requirements: macOS 26, Xcode 26.
