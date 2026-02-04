//
//  PluralMacApp.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import SwiftUI

@main
struct PluralMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Disable default new window command
            }
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
