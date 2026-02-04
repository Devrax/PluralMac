//
//  InstanceDetailView.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import SwiftUI
import AppKit

/// Detail view showing full information about a selected instance.
struct InstanceDetailView: View {
    
    // MARK: - Properties
    
    let instance: AppInstance
    @Bindable var viewModel: InstanceViewModel
    
    @State private var appIcon: NSImage?
    @State private var isRenaming = false
    @State private var newName: String = ""
    @State private var showDeleteConfirmation = false
    @State private var deleteData = false
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                Divider()
                
                // Info sections
                targetAppSection
                
                Divider()
                
                dataIsolationSection
                
                if !instance.environmentVariables.isEmpty {
                    Divider()
                    environmentSection
                }
                
                if !instance.commandLineArguments.isEmpty {
                    Divider()
                    argumentsSection
                }
                
                Divider()
                
                timestampsSection
                
                Spacer()
            }
            .padding(24)
        }
        .frame(minWidth: 400)
        .toolbar {
            toolbarContent
        }
        .task {
            await loadIcon()
        }
        .alert("Rename Instance", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task {
                    try? await viewModel.renameInstance(instance, to: newName)
                }
            }
        }
        .confirmationDialog(
            "Delete Instance",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Shortcut Only", role: .destructive) {
                Task {
                    try? await viewModel.deleteInstance(instance, deleteData: false)
                }
            }
            Button("Delete Shortcut & Data", role: .destructive) {
                Task {
                    try? await viewModel.deleteInstance(instance, deleteData: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to delete just the shortcut, or also delete all isolated data?")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Icon
            Group {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Name and type
            VStack(alignment: .leading, spacing: 4) {
                Text(instance.name)
                    .font(.title)
                    .fontWeight(.semibold)
                
                HStack(spacing: 6) {
                    Image(systemName: instance.targetAppType.compatibilityLevel.symbolName)
                        .foregroundStyle(compatibilityColor)
                    
                    Text(instance.targetAppType.displayName)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            
            Spacer()
            
            // Launch button
            Button {
                Task {
                    try? await viewModel.launchInstance(instance)
                }
            } label: {
                Label("Launch", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private var compatibilityColor: Color {
        switch instance.targetAppType.compatibilityLevel {
        case .full: return .green
        case .partial: return .yellow
        case .unsupported: return .red
        }
    }
    
    // MARK: - Target App Section
    
    private var targetAppSection: some View {
        DetailSection(title: "Target Application") {
            DetailRow(label: "Application", value: targetAppName)
            DetailRow(label: "Bundle ID", value: instance.targetBundleIdentifier)
            DetailRow(label: "Path", value: instance.targetAppPath.path)
                .contextMenu {
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(instance.targetAppPath.path, forType: .string)
                    }
                    Button("Show in Finder") {
                        LaunchServicesHelper.revealInFinder(instance.targetAppPath)
                    }
                }
        }
    }
    
    private var targetAppName: String {
        instance.targetAppPath.deletingPathExtension().lastPathComponent
    }
    
    // MARK: - Data Isolation Section
    
    private var dataIsolationSection: some View {
        DetailSection(title: "Data Isolation") {
            DetailRow(label: "Method", value: instance.effectiveIsolationMethod.rawValue.capitalized)
            DetailRow(label: "Data Path", value: instance.dataPath.path)
                .contextMenu {
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(instance.dataPath.path, forType: .string)
                    }
                    Button("Show in Finder") {
                        viewModel.revealDataInFinder(instance)
                    }
                }
            DetailRow(label: "Shortcut Path", value: instance.shortcutPath.path)
                .contextMenu {
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(instance.shortcutPath.path, forType: .string)
                    }
                    Button("Show in Finder") {
                        viewModel.revealInFinder(instance)
                    }
                }
        }
    }
    
    // MARK: - Environment Section
    
    private var environmentSection: some View {
        DetailSection(title: "Environment Variables") {
            ForEach(Array(instance.environmentVariables.keys.sorted()), id: \.self) { key in
                DetailRow(label: key, value: instance.environmentVariables[key] ?? "")
            }
        }
    }
    
    // MARK: - Arguments Section
    
    private var argumentsSection: some View {
        DetailSection(title: "Command Line Arguments") {
            ForEach(instance.commandLineArguments, id: \.self) { arg in
                Text(arg)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Timestamps Section
    
    private var timestampsSection: some View {
        DetailSection(title: "Information") {
            DetailRow(label: "Created", value: instance.createdAtFormatted)
            if let lastLaunched = instance.lastLaunchedAtFormatted {
                DetailRow(label: "Last Launched", value: lastLaunched)
            }
            DetailRow(label: "Instance ID", value: instance.id.uuidString)
                .contextMenu {
                    Button("Copy ID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(instance.id.uuidString, forType: .string)
                    }
                }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.revealInFinder(instance)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .help("Show shortcut in Finder")
            
            Menu {
                Button {
                    newName = instance.name
                    isRenaming = true
                } label: {
                    Label("Rename...", systemImage: "pencil")
                }
                
                Button {
                    Task {
                        try? await viewModel.duplicateInstance(instance, newName: "\(instance.name) Copy")
                    }
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete...", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
    
    // MARK: - Icon Loading
    
    @MainActor
    private func loadIcon() async {
        if instance.shortcutExists {
            appIcon = NSWorkspace.shared.icon(forFile: instance.shortcutPath.path)
        } else {
            appIcon = NSWorkspace.shared.icon(forFile: instance.targetAppPath.path)
        }
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            
            Text(value)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .font(.body)
    }
}

// MARK: - Preview

#Preview {
    let mockInstance = AppInstance(
        name: "Chrome Work",
        application: try! Application(from: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
    )
    
    return InstanceDetailView(
        instance: mockInstance,
        viewModel: InstanceViewModel()
    )
}
