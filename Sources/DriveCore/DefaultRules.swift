/// The cleanup rules DriveManager ships with. A `rules.json` file in
/// DriveManager's Application Support folder can add rules or replace these
/// by id, in the same format.
let defaultRulesJSON = #"""
[
  {
    "id": "app-caches",
    "title": "App caches",
    "detail": "Files apps keep to start faster. They are rebuilt when needed.",
    "level": "safe",
    "paths": ["~/Library/Caches/*"],
    "minSize": 10000000
  },
  {
    "id": "logs",
    "title": "Logs",
    "detail": "Records of what apps did. Only useful when tracking down a problem.",
    "level": "safe",
    "paths": ["~/Library/Logs/*"],
    "minSize": 1000000
  },
  {
    "id": "xcode-derived-data",
    "title": "Xcode build files",
    "detail": "Intermediate build products. Xcode rebuilds them on the next build.",
    "level": "safe",
    "paths": ["~/Library/Developer/Xcode/DerivedData/*"]
  },
  {
    "id": "xcode-device-support",
    "title": "Old iOS device support",
    "detail": "Debug symbols copied from devices. Xcode copies them again when a device connects.",
    "level": "safe",
    "paths": ["~/Library/Developer/Xcode/iOS DeviceSupport/*", "~/Library/Developer/Xcode/watchOS DeviceSupport/*"],
    "minAgeDays": 90
  },
  {
    "id": "simulator-caches",
    "title": "Simulator caches",
    "detail": "Caches of the iOS Simulator, rebuilt on demand.",
    "level": "safe",
    "paths": ["~/Library/Developer/CoreSimulator/Caches/*"]
  },
  {
    "id": "package-caches",
    "title": "Developer package caches",
    "detail": "Downloaded packages kept by npm, Gradle and similar tools. They download again when needed.",
    "level": "safe",
    "paths": ["~/.npm/_cacache", "~/.gradle/caches", "~/.cocoapods/repos", "~/.cache/*"],
    "minSize": 50000000
  },
  {
    "id": "old-downloads",
    "title": "Old downloads",
    "detail": "Large files in Downloads you have not touched for three months.",
    "level": "review",
    "paths": ["~/Downloads/*"],
    "minSize": 50000000,
    "minAgeDays": 90
  },
  {
    "id": "installers",
    "title": "Installers",
    "detail": "Disk images and packages, usually not needed once the app is installed.",
    "level": "review",
    "paths": ["~/Downloads/*.dmg", "~/Downloads/*.pkg", "~/Downloads/*.zip"],
    "minSize": 10000000
  },
  {
    "id": "simulator-devices",
    "title": "iOS simulators",
    "detail": "Simulated devices with their apps and data. Xcode can create them again.",
    "level": "review",
    "paths": ["~/Library/Developer/CoreSimulator/Devices/*"],
    "minSize": 100000000
  },
  {
    "id": "xcode-archives",
    "title": "Xcode archives",
    "detail": "Builds kept for submitting or debugging releases.",
    "level": "review",
    "paths": ["~/Library/Developer/Xcode/Archives/*"]
  },
  {
    "id": "android-emulators",
    "title": "Android emulators",
    "detail": "Virtual devices of Android Studio, with their system images and data.",
    "level": "careful",
    "paths": ["~/.android/avd/*"],
    "minSize": 100000000
  },
  {
    "id": "device-backups",
    "title": "iPhone and iPad backups",
    "detail": "Local backups made by Finder. Keep the latest one unless it is also in iCloud.",
    "level": "careful",
    "paths": ["~/Library/Application Support/MobileSync/Backup/*"]
  }
]
"""#
