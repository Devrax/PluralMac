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
