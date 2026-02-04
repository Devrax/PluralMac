//
//  PluralMacApp.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct PluralMacApp: App {
    
    @State private var showImportSheet = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .fileImporter(
                    isPresented: $showImportSheet,
                    allowedContentTypes: [UTType.json],
                    allowsMultipleSelection: false
                ) { result in
                    handleImport(result)
                }
        }
        .windowStyle(.automatic)
        .commands {
            // Custom commands
            PluralMacCommands(showImportSheet: $showImportSheet)
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            NotificationCenter.default.post(
                name: .importInstances,
                object: nil,
                userInfo: ["url": url]
            )
        case .failure(let error):
            print("Import error: \(error.localizedDescription)")
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load compatibility database on launch
        Task {
            await CompatibilityDatabase.shared.load()
        }
        
        // Setup menu bar if enabled in preferences
        let showMenuBar = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        if showMenuBar {
            Task { @MainActor in
                MenuBarManager.shared.isMenuBarIconVisible = true
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit if menu bar icon is visible
        return !MenuBarManager.shared.isMenuBarIconVisible
    }
}

// MARK: - Custom Commands

struct PluralMacCommands: Commands {
    @Binding var showImportSheet: Bool
    
    var body: some Commands {
        // Replace new item with our own
        CommandGroup(replacing: .newItem) {
            Button("New Instance...") {
                NotificationCenter.default.post(name: .showCreateInstance, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        
        // Import/Export
        CommandGroup(after: .importExport) {
            Button("Import Instances...") {
                showImportSheet = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            
            Button("Export All Instances...") {
                NotificationCenter.default.post(name: .exportAllInstances, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        
        // Instance actions
        CommandMenu("Instance") {
            Button("Launch Selected") {
                NotificationCenter.default.post(name: .launchSelectedInstance, object: nil)
            }
            .keyboardShortcut(.return, modifiers: .command)
            
            Divider()
            
            Button("Show in Finder") {
                NotificationCenter.default.post(name: .revealSelectedInstance, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            
            Button("Show Data in Finder") {
                NotificationCenter.default.post(name: .revealSelectedInstanceData, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Duplicate...") {
                NotificationCenter.default.post(name: .duplicateSelectedInstance, object: nil)
            }
            .keyboardShortcut("d", modifiers: .command)
            
            Button("Rename...") {
                NotificationCenter.default.post(name: .renameSelectedInstance, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Divider()
            
            Button("Delete...") {
                NotificationCenter.default.post(name: .deleteSelectedInstance, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let importInstances = Notification.Name("com.mtech.PluralMac.importInstances")
    static let showCreateInstance = Notification.Name("com.mtech.PluralMac.showCreateInstance")
    static let exportAllInstances = Notification.Name("com.mtech.PluralMac.exportAllInstances")
    static let launchSelectedInstance = Notification.Name("com.mtech.PluralMac.launchSelectedInstance")
    static let revealSelectedInstance = Notification.Name("com.mtech.PluralMac.revealSelectedInstance")
    static let revealSelectedInstanceData = Notification.Name("com.mtech.PluralMac.revealSelectedInstanceData")
    static let duplicateSelectedInstance = Notification.Name("com.mtech.PluralMac.duplicateSelectedInstance")
    static let renameSelectedInstance = Notification.Name("com.mtech.PluralMac.renameSelectedInstance")
    static let deleteSelectedInstance = Notification.Name("com.mtech.PluralMac.deleteSelectedInstance")
}
