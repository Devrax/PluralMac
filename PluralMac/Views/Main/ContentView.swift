//
//  ContentView.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import SwiftUI

/// Main content view of the application.
/// Uses a NavigationSplitView with sidebar list and detail view.
struct ContentView: View {
    
    // MARK: - Properties
    
    @State private var viewModel = InstanceViewModel()
    @State private var showingCreateSheet = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showingImportResults = false
    @State private var importResults: [ImportValidationResult] = []
    @State private var showingRenameSheet = false
    @State private var showingDuplicateSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var renameName = ""
    @State private var duplicateName = ""
    
    @EnvironmentObject private var menuBarManager: MenuBarManager
    
    // MARK: - Body
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: Instance List
            sidebarContent
        } detail: {
            // Detail: Selected instance or empty state
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 450)
        .task {
            await viewModel.loadInstances()
            menuBarManager.updateInstances(viewModel.instances)
        }
        .onChange(of: viewModel.instances) { _, newInstances in
            menuBarManager.updateInstances(newInstances)
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateInstanceView(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .onReceive(NotificationCenter.default.publisher(for: .importInstances)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                Task {
                    await handleImport(from: url)
                }
            }
        }
        .alert("Import Instances", isPresented: $showingImportResults) {
            Button("Import Valid") {
                Task {
                    let validConfigs = importResults.filter { $0.isValid }.map { $0.config }
                    try? await viewModel.createFromImport(validConfigs)
                }
            }
            .disabled(importResults.filter { $0.isValid }.isEmpty)
            
            Button("Cancel", role: .cancel) {}
        } message: {
            let validCount = importResults.filter { $0.isValid }.count
            let invalidCount = importResults.filter { !$0.isValid }.count
            
            if invalidCount > 0 {
                Text("Found \(validCount) valid and \(invalidCount) invalid instance(s). Only valid instances can be imported.")
            } else {
                Text("Ready to import \(validCount) instance(s).")
            }
        }
        // Handle keyboard shortcut notifications
        .onReceive(NotificationCenter.default.publisher(for: .showCreateInstance)) { _ in
            showingCreateSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportAllInstances)) { _ in
            exportAllInstances()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchSelectedInstance)) { _ in
            if let instance = viewModel.selectedInstance {
                Task { try? await viewModel.launchInstance(instance) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .revealSelectedInstance)) { _ in
            if let instance = viewModel.selectedInstance {
                viewModel.revealInFinder(instance)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .revealSelectedInstanceData)) { _ in
            if let instance = viewModel.selectedInstance {
                viewModel.revealDataInFinder(instance)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .duplicateSelectedInstance)) { _ in
            if let instance = viewModel.selectedInstance {
                duplicateName = "\(instance.name) Copy"
                showingDuplicateSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .renameSelectedInstance)) { _ in
            if let instance = viewModel.selectedInstance {
                renameName = instance.name
                showingRenameSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedInstance)) { _ in
            if viewModel.selectedInstance != nil {
                showingDeleteConfirmation = true
            }
        }
        // Additional dialogs
        .alert("Rename Instance", isPresented: $showingRenameSheet) {
            TextField("Name", text: $renameName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let instance = viewModel.selectedInstance {
                    Task { try? await viewModel.renameInstance(instance, to: renameName) }
                }
            }
        }
        .alert("Duplicate Instance", isPresented: $showingDuplicateSheet) {
            TextField("Name", text: $duplicateName)
            Button("Cancel", role: .cancel) {}
            Button("Duplicate") {
                if let instance = viewModel.selectedInstance {
                    Task { try? await viewModel.duplicateInstance(instance, newName: duplicateName) }
                }
            }
        }
        .confirmationDialog("Delete Instance", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Shortcut Only", role: .destructive) {
                if let instance = viewModel.selectedInstance {
                    Task { try? await viewModel.deleteInstance(instance, deleteData: false) }
                }
            }
            Button("Delete Shortcut & Data", role: .destructive) {
                if let instance = viewModel.selectedInstance {
                    Task { try? await viewModel.deleteInstance(instance, deleteData: true) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to delete just the shortcut, or also delete all isolated data?")
        }
    }
    
    // MARK: - Export All
    
    private func exportAllInstances() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PluralMac-Backup.json"
        panel.title = "Export All Instances"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                try? await viewModel.exportAllInstances(to: url)
            }
        }
    }
    
    // MARK: - Import Handler
    
    private func handleImport(from url: URL) async {
        do {
            importResults = try await viewModel.importInstances(from: url)
            showingImportResults = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
        }
    }
    
    // MARK: - Sidebar Content
    
    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Instance list
            if viewModel.hasInstances {
                InstanceListView(viewModel: viewModel)
            } else {
                EmptyStateView(onCreateTapped: {
                    showingCreateSheet = true
                })
            }
        }
        .safeAreaInset(edge: .bottom) {
            sidebarToolbar
        }
        .navigationTitle("Instances")
        .searchable(text: $viewModel.searchText, prompt: "Search instances")
    }
    
    // MARK: - Sidebar Toolbar
    
    private var sidebarToolbar: some View {
        HStack {
            Button {
                showingCreateSheet = true
            } label: {
                Label("New Instance", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            
            Spacer()
            
            Text("\(viewModel.instanceCount) instance\(viewModel.instanceCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
    }
    
    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        if let instance = viewModel.selectedInstance {
            InstanceDetailView(instance: instance, viewModel: viewModel)
        } else {
            noSelectionView
        }
    }
    
    // MARK: - No Selection View
    
    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("No Instance Selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("Select an instance from the sidebar or create a new one")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            
            Button {
                showingCreateSheet = true
            } label: {
                Label("Create Instance", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
