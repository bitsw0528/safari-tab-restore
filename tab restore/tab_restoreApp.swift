//
//  tab_restoreApp.swift
//  tab restore
//
//  Created by Wayne Yao on 11/4/25.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
/// Application entry point: configures the main window that hosts `ContentView`.
struct RestoreTabsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Restore Tabs") {
            ContentView()
        }
        // Provide a sensible default window size so the tab list fits comfortably.
        .defaultSize(width: 620, height: 520)
    }
}
