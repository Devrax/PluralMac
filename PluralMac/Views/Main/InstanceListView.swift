//
//  InstanceListView.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import SwiftUI

/// List view showing all app instances in the sidebar.
struct InstanceListView: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: InstanceViewModel
    
    // MARK: - Body
    
    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedInstance?.id },
            set: { id in
                viewModel.selectedInstance = viewModel.instances.first { $0.id == id }
            }
        )) {
            ForEach(viewModel.filteredInstances) { instance in
                InstanceRowView(instance: instance, viewModel: viewModel)
                    .tag(instance.id)
            }
            .onDelete(perform: deleteInstances)
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            // Double-click to launch
            if let id = ids.first,
               let instance = viewModel.instances.first(where: { $0.id == id }) {
                Task {
                    try? await viewModel.launchInstance(instance)
                }
            }
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private func contextMenuContent(for ids: Set<UUID>) -> some View {
        let selectedInstances = viewModel.instances.filter { ids.contains($0.id) }
        
        if selectedInstances.count == 1, let instance = selectedInstances.first {
            // Single selection menu
            Button {
                Task {
                    try? await viewModel.launchInstance(instance)
                }
            } label: {
                Label("Launch", systemImage: "play.fill")
            }
            
            Divider()
            
            Button {
                viewModel.revealInFinder(instance)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            
            Button {
                viewModel.revealDataInFinder(instance)
            } label: {
                Label("Show Data Folder", systemImage: "folder.badge.gearshape")
            }
            
            Divider()
            
            Button {
                Task {
                    try? await viewModel.duplicateInstance(instance, newName: "\(instance.name) Copy")
                }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            
            Divider()
            
            Button(role: .destructive) {
                Task {
                    try? await viewModel.deleteInstance(instance, deleteData: false)
                }
            } label: {
                Label("Delete Shortcut", systemImage: "trash")
            }
            
            Button(role: .destructive) {
                Task {
                    try? await viewModel.deleteInstance(instance, deleteData: true)
                }
            } label: {
                Label("Delete Shortcut & Data", systemImage: "trash.fill")
            }
        } else if selectedInstances.count > 1 {
            // Multi-selection menu
            Button(role: .destructive) {
                Task {
                    try? await viewModel.deleteInstances(selectedInstances, deleteData: false)
                }
            } label: {
                Label("Delete \(selectedInstances.count) Shortcuts", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Actions
    
    private func deleteInstances(at offsets: IndexSet) {
        let instancesToDelete = offsets.map { viewModel.filteredInstances[$0] }
        Task {
            try? await viewModel.deleteInstances(instancesToDelete, deleteData: false)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var viewModel = InstanceViewModel()
    
    InstanceListView(viewModel: viewModel)
        .frame(width: 280)
}
