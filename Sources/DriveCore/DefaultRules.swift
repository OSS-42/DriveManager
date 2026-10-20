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
    "minSize": 10000000,
    "explain": {
      "what": "Copies of things apps already downloaded or worked out once, such as pictures, web pages and previews. Apps keep them so they open faster next time.",
      "why": "Every app writes its own cache and few of them ever clean up, so caches grow quietly over months.",
      "how": "Move them to the Trash. Apps rebuild what they need the next time they run, so a few things may load a bit slower once. Quit the app first if it is open. They come back over time, which is normal."
    }
  },
  {
    "id": "logs",
    "title": "Logs",
    "detail": "Records of what apps did. Only useful when tracking down a problem.",
    "level": "safe",
    "paths": ["~/Library/Logs/*"],
    "minSize": 1000000,
    "explain": {
      "what": "Diary files where apps write down what they did, mostly so a developer can find a bug.",
      "why": "Apps add to them every day and many never delete old ones.",
      "how": "Move them to the Trash. Nothing stops working. Keep them only if you are tracking down a crash and someone asked you for the logs."
    }
  },
  {
    "id": "xcode-derived-data",
    "title": "Xcode build files",
    "detail": "Intermediate build products. Xcode rebuilds them on the next build.",
    "level": "safe",
    "paths": ["~/Library/Developer/Xcode/DerivedData/*"],
    "explain": {
      "what": "Half-finished pieces Xcode makes while it builds your apps: compiled code, indexes and previews.",
      "why": "Xcode keeps a folder for every project you ever built, even ones you deleted long ago.",
      "how": "Move them to the Trash with Xcode closed. The next build of a project takes longer while Xcode makes them again. Projects you no longer open never come back."
    }
  },
  {
    "id": "xcode-device-support",
    "title": "Old iOS device support",
    "detail": "Debug symbols copied from devices. Xcode copies them again when a device connects.",
    "level": "safe",
    "paths": ["~/Library/Developer/Xcode/iOS DeviceSupport/*", "~/Library/Developer/Xcode/watchOS DeviceSupport/*"],
    "minAgeDays": 90,
    "explain": {
      "what": "Copies of the system files of each iPhone or Apple Watch you plugged in, so Xcode can debug apps on it.",
      "why": "Xcode makes a new copy for every iOS version your devices ran, and keeps the old ones after you update.",
      "how": "Move the old versions to the Trash. If you plug in a device on that version again, Xcode copies the files again, which takes a few minutes."
    }
  },
  {
    "id": "simulator-caches",
    "title": "Simulator caches",
    "detail": "Caches of the iOS Simulator, rebuilt on demand.",
    "level": "safe",
    "paths": ["~/Library/Developer/CoreSimulator/Caches/*"],
    "explain": {
      "what": "Temporary files of the iOS Simulator, such as prepared app data and shader caches.",
      "why": "The Simulator writes them while you run apps and does not clean them up.",
      "how": "Move them to the Trash with the Simulator closed. It rebuilds them when it starts."
    }
  },
  {
    "id": "package-caches",
    "title": "Developer package caches",
    "detail": "Downloaded packages kept by npm, Gradle and similar tools. They download again when needed.",
    "level": "safe",
    "paths": ["~/.npm/_cacache", "~/.gradle/caches", "~/.cocoapods/repos", "~/.cache/*"],
    "minSize": 50000000,
    "explain": {
      "what": "Libraries that npm, Gradle, CocoaPods and other developer tools downloaded for your projects, kept so they don't download them again.",
      "why": "Every version of every library any project ever asked for stays here, even after the project moved on.",
      "how": "Move them to the Trash. The next build of each project downloads what it needs again, so it is slower once and needs internet."
    }
  },
  {
    "id": "old-downloads",
    "title": "Old downloads",
    "detail": "Large files in Downloads you have not touched for three months.",
    "level": "review",
    "paths": ["~/Downloads/*"],
    "minSize": 50000000,
    "minAgeDays": 90,
    "explain": {
      "what": "Large files in your Downloads folder that you have not opened or changed for three months.",
      "why": "Downloads keeps everything until you delete it, and most files are used once.",
      "how": "Look through the list and keep what you still want somewhere better, such as Documents. Move the rest to the Trash."
    }
  },
  {
    "id": "installers",
    "title": "Installers",
    "detail": "Disk images and packages, usually not needed once the app is installed.",
    "level": "review",
    "paths": ["~/Downloads/*.dmg", "~/Downloads/*.pkg", "~/Downloads/*.zip"],
    "minSize": 10000000,
    "explain": {
      "what": "Disk images (.dmg), packages (.pkg) and zip files, usually the box an app came in.",
      "why": "Once an app is installed, the installer is left behind in Downloads.",
      "how": "Make sure the app is installed and that you can download it again, then move the installer to the Trash."
    }
  },
  {
    "id": "simulator-devices",
    "title": "iOS simulators",
    "detail": "Simulated devices with their apps and data. Xcode can create them again.",
    "level": "review",
    "paths": ["~/Library/Developer/CoreSimulator/Devices/*"],
    "minSize": 100000000,
    "explain": {
      "what": "Pretend iPhones and iPads that Xcode uses to run your apps on the Mac. Each one holds a whole iOS, plus the apps and data you put on it.",
      "why": "Xcode creates a set of them for every iOS version it installs and keeps them after you stop using that version.",
      "how": "Delete the ones you don't use in Xcode under Window > Devices and Simulators, or run `xcrun simctl delete unavailable` in Terminal to remove those for iOS versions you no longer have. Xcode can create any of them again."
    }
  },
  {
    "id": "xcode-archives",
    "title": "Xcode archives",
    "detail": "Builds kept for submitting or debugging releases.",
    "level": "review",
    "paths": ["~/Library/Developer/Xcode/Archives/*"],
    "explain": {
      "what": "Finished builds of your apps that Xcode keeps after Product > Archive, with the symbols needed to read crash reports.",
      "why": "Xcode keeps every archive you ever made.",
      "how": "Keep the archives of versions people still use, because you need them to read their crash reports. Delete older ones in Xcode under Window > Organizer, or move them to the Trash here."
    }
  },
  {
    "id": "android-emulators",
    "title": "Android emulators",
    "detail": "Virtual devices of Android Studio, with their system images and data.",
    "level": "careful",
    "paths": ["~/.android/avd/*"],
    "minSize": 100000000,
    "explain": {
      "what": "Pretend Android phones that Android Studio runs on your Mac, each with its own system and storage.",
      "why": "Each emulator you create in Android Studio keeps its own disk, which grows as you use it.",
      "how": "Delete the ones you don't need in Android Studio under Device Manager, so its list stays right. Its data and installed apps are lost; the emulator can be created again."
    }
  },
  {
    "id": "device-backups",
    "title": "iPhone and iPad backups",
    "detail": "Local backups made by Finder. Keep the latest one unless it is also in iCloud.",
    "level": "careful",
    "paths": ["~/Library/Application Support/MobileSync/Backup/*"],
    "explain": {
      "what": "Full backups of your iPhone or iPad that Finder made on this Mac.",
      "why": "Finder keeps one backup per device, including devices you no longer have.",
      "how": "Keep the backup of a device you still use unless it is also backed up to iCloud. Delete old ones in Finder: select the device, Manage Backups. A deleted backup cannot be brought back."
    }
  },
  {
    "id": "old-app-builds",
    "title": "Old app builds",
    "detail": "Earlier Android and iOS builds of your apps. The newest build in each folder is kept. Older ones may be the only copy of a version you released.",
    "level": "review",
    "paths": ["~/**/*.apk", "~/**/*.aab", "~/**/*.ipa"],
    "exceptPaths": ["~/Library"],
    "minSize": 1000000,
    "keepNewest": true,
    "explain": {
      "what": "Earlier APK, AAB or IPA files of your own apps: the finished app files you install on a phone or send to a store.",
      "why": "Each release script or build drops a new file next to the old ones and nothing removes them.",
      "how": "Keep any version that people still run or that you may need to roll back to. Move the others to the Trash. The newest file of each type in each folder is never suggested. To stop them piling up, have your release script delete older builds."
    }
  }
]
"""#
