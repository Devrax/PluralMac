//
//  EmptyStateView.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import SwiftUI

/// View shown when there are no instances created yet.
struct EmptyStateView: View {
    
    // MARK: - Properties
    
    var onCreateTapped: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Icon
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            
            // Title
            Text("No Instances Yet")
                .font(.title2)
                .fontWeight(.medium)
            
            // Description
            Text("Create your first app instance to run multiple copies of the same app with isolated data.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            
            // Create button
            Button(action: onCreateTapped) {
                Label("Create Instance", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
            
            Spacer()
            
            // Help text
            helpSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Help Section
    
    private var helpSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 40)
            
            Text("How it works")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 24) {
                helpItem(
                    icon: "app.badge.checkmark",
                    text: "Select an app"
                )
                
                helpItem(
                    icon: "folder.badge.gearshape",
                    text: "Isolated data"
                )
                
                helpItem(
                    icon: "dock.rectangle",
                    text: "Pin to Dock"
                )
            }
            .padding(.bottom, 8)
        }
    }
    
    private func helpItem(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text(text)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Preview

#Preview {
    EmptyStateView(onCreateTapped: {})
        .frame(width: 300, height: 500)
}
