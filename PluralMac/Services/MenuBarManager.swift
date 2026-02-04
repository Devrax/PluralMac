//
//  MenuBarManager.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import AppKit
import SwiftUI
import OSLog

/// Manages the menu bar (status bar) icon and menu for quick access to instances.
@MainActor
final class MenuBarManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = MenuBarManager()
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "MenuBarManager")
    
    /// Whether the menu bar icon is currently shown
    @Published var isMenuBarIconVisible: Bool = false {
        didSet {
            if isMenuBarIconVisible {
                setupStatusItem()
            } else {
                removeStatusItem()
            }
        }
    }
    
    /// Current instances for the menu
    @Published var instances: [AppInstance] = []
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup
    
    /// Setup the status bar item
    func setupStatusItem() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "PluralMac")
            button.image?.isTemplate = true
            button.toolTip = "PluralMac - Quick Launch"
        }
        
        updateMenu()
        logger.info("Menu bar icon enabled")
    }
    
    /// Remove the status bar item
    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            logger.info("Menu bar icon disabled")
        }
    }
    
    /// Update the menu with current instances
    func updateMenu() {
        let menu = NSMenu()
        
        // Header
        let headerItem = NSMenuItem(title: "PluralMac", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quick launch section
        if instances.isEmpty {
            let noInstancesItem = NSMenuItem(title: "No instances", action: nil, keyEquivalent: "")
            noInstancesItem.isEnabled = false
            menu.addItem(noInstancesItem)
        } else {
            // Group instances by target app
            let grouped = Dictionary(grouping: instances) { $0.targetBundleIdentifier }
            
            for (bundleId, appInstances) in grouped.sorted(by: { $0.key < $1.key }) {
                // App name as section header
                if let firstInstance = appInstances.first {
                    let appName = firstInstance.targetAppPath.deletingPathExtension().lastPathComponent
                    
                    if grouped.count > 1 {
                        let appHeader = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
                        appHeader.isEnabled = false
                        menu.addItem(appHeader)
                    }
                    
                    // Individual instances
                    for instance in appInstances.sorted(by: { $0.name < $1.name }) {
                        let item = NSMenuItem(
                            title: instance.name,
                            action: #selector(launchInstance(_:)),
                            keyEquivalent: ""
                        )
                        item.target = self
                        item.representedObject = instance
                        
                        // Load icon
                        if instance.shortcutExists {
                            let icon = NSWorkspace.shared.icon(forFile: instance.shortcutPath.path)
                            icon.size = NSSize(width: 16, height: 16)
                            item.image = icon
                        }
                        
                        menu.addItem(item)
                    }
                    
                    if grouped.count > 1 {
                        menu.addItem(NSMenuItem.separator())
                    }
                }
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Actions section
        let createItem = NSMenuItem(
            title: "Create New Instance...",
            action: #selector(showCreateWindow),
            keyEquivalent: "n"
        )
        createItem.keyEquivalentModifierMask = [.command, .shift]
        createItem.target = self
        menu.addItem(createItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Show main window
        let showWindowItem = NSMenuItem(
            title: "Show PluralMac",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        menu.addItem(showWindowItem)
        
        // Preferences
        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit PluralMac",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    // MARK: - Actions
    
    @objc private func launchInstance(_ sender: NSMenuItem) {
        guard let instance = sender.representedObject as? AppInstance else { return }
        
        Task {
            do {
                _ = try await LaunchServicesHelper.launchAsync(instance.shortcutPath)
                logger.info("Launched instance from menu bar: \(instance.name)")
            } catch {
                logger.error("Failed to launch instance: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Find and focus the main window
        if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue != "com_apple_SwiftUI_Settings_window" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func showCreateWindow() {
        showMainWindow()
        
        // Post notification to show create sheet
        NotificationCenter.default.post(name: .showCreateInstance, object: nil)
    }
    
    @objc private func showPreferences() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Open Settings window
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    
    // MARK: - Instance Updates
    
    /// Update the instances displayed in the menu
    func updateInstances(_ newInstances: [AppInstance]) {
        self.instances = newInstances
        updateMenu()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showCreateInstance = Notification.Name("com.mtech.PluralMac.showCreateInstance")
}
