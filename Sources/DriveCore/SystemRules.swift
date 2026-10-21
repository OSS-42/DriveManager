/// Cleanup rules for files outside the home folder that belong to macOS or
/// to every user of the Mac. They run only when the user asks to check
/// macOS files, and most of their items need an administrator password to
/// move.
let systemRulesJSON = #"""
[
  {
    "id": "macos-installers",
    "title": "macOS installers",
    "detail": "Full installers of macOS, kept in Applications after an upgrade.",
    "level": "review",
    "paths": ["/Applications/Install macOS*.app"],
    "explain": {
      "what": "The complete installer of a macOS version, the app named \"Install macOS …\". It weighs 12 to 15 GB.",
      "why": "It is left in Applications when you download macOS from the App Store or with softwareupdate, and stays after the upgrade is done.",
      "how": "Keep it only if you plan to make a bootable USB stick or install that version on another Mac. Otherwise move it to the Trash. You can download it again from the App Store."
    }
  },
  {
    "id": "old-update-downloads",
    "title": "Old update downloads",
    "detail": "Software updates downloaded by older versions of macOS.",
    "level": "review",
    "paths": ["/Library/Updates/*"],
    "minSize": 10000000,
    "explain": {
      "what": "Update packages that macOS downloaded before installing them.",
      "why": "Older versions of macOS kept updates here and sometimes left them behind after installing. Recent versions stage updates in a protected part of the disk and clear it themselves.",
      "how": "Make sure no update is waiting to install (System Settings > General > Software Update), then drag these to the Trash in Finder. Finder asks for your password."
    }
  },
  {
    "id": "system-caches",
    "title": "System caches",
    "detail": "Caches shared by all users of this Mac, rebuilt when needed.",
    "level": "safe",
    "paths": ["/Library/Caches/*"],
    "minSize": 10000000,
    "explain": {
      "what": "The same kind of cache as in your own Library, but kept by system services and apps for every user of the Mac.",
      "why": "Services write caches here and rarely trim them.",
      "how": "Drag them to the Trash in Finder, which asks for your password, then restart the Mac so services rebuild what they need. Some come back right away, which is normal."
    }
  },
  {
    "id": "system-logs",
    "title": "System logs and crash reports",
    "detail": "Records kept by macOS and system services, useful only to track down a problem.",
    "level": "safe",
    "paths": ["/Library/Logs/*", "/private/var/log/*"],
    "minSize": 1000000,
    "explain": {
      "what": "Log files and crash reports written by macOS, installers and background services.",
      "why": "They pile up over the life of the Mac. macOS trims some of them, not all.",
      "how": "Drag them to the Trash in Finder, which asks for your password. Keep them if you are tracking down a crash or someone asked you to send them."
    }
  }
]
"""#
