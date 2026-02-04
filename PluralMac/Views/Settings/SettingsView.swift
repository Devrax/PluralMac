//
//  SettingsView.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import SwiftUI

/// Settings view accessible via Preferences menu (Cmd+,)
struct SettingsView: View {
    
    // MARK: - Properties
    
    @AppStorage("defaultDataDirectory") private var defaultDataDirectory: String = ""
    @AppStorage("showDockBadges") private var showDockBadges: Bool = true
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete: Bool = true
    
    @State private var selectedTab: SettingsTab = .general
    
    // MARK: - Body
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(
                defaultDataDirectory: $defaultDataDirectory,
                confirmBeforeDelete: $confirmBeforeDelete
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(SettingsTab.general)
            
            AppearanceSettingsTab(showDockBadges: $showDockBadges)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)
            
            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable {
    case general
    case appearance
    case about
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @Binding var defaultDataDirectory: String
    @Binding var confirmBeforeDelete: Bool
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Data Directory", text: $defaultDataDirectory, prompt: Text("Default"))
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Choose...") {
                        chooseDirectory()
                    }
                    
                    if !defaultDataDirectory.isEmpty {
                        Button {
                            defaultDataDirectory = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Text("Where instance data is stored. Leave empty for default location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Storage")
            }
            
            Section {
                Toggle("Confirm before deleting instances", isOn: $confirmBeforeDelete)
            } header: {
                Text("Safety")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose the directory where instance data will be stored"
        
        if panel.runModal() == .OK, let url = panel.url {
            defaultDataDirectory = url.path
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsTab: View {
    @Binding var showDockBadges: Bool
    
    var body: some View {
        Form {
            Section {
                Toggle("Show badges on Dock icons", isOn: $showDockBadges)
                
                Text("Display notification badges on instance Dock icons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Dock")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Settings

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            Text("PluralMac")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Run multiple instances of macOS apps\nwith isolated data storage.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            HStack {
                Link("Website", destination: URL(string: "https://pluralmac.com")!)
                Text("•")
                    .foregroundStyle(.tertiary)
                Link("GitHub", destination: URL(string: "https://github.com/mtech/PluralMac")!)
            }
            .font(.caption)
            
            Text("© 2026 MTech. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
