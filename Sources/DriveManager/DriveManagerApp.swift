import AppKit
import SwiftUI

@main
struct DriveManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("DriveManager") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DriveManager") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(
                            string: "See what takes space on your disk and clear it safely.",
                            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                        ),
                    ])
                }
            }
        }
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started with `swift run`, outside an app bundle, macOS treats the
        // process as a background tool: no Dock icon and no focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
