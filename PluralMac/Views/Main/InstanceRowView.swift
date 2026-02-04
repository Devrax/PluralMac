//
//  InstanceRowView.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import SwiftUI
import AppKit

/// A single row in the instance list showing instance icon, name, and target app.
struct InstanceRowView: View {
    
    // MARK: - Properties
    
    let instance: AppInstance
    @Bindable var viewModel: InstanceViewModel
    
    @State private var appIcon: NSImage?
    @State private var isHovering = false
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            iconView
            
            // Instance Info
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    // App type indicator
                    compatibilityIndicator
                    
                    Text(targetAppName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Quick launch button (shown on hover)
            if isHovering {
                Button {
                    Task {
                        try? await viewModel.launchInstance(instance)
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Launch")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .task {
            await loadIcon()
        }
    }
    
    // MARK: - Icon View
    
    @ViewBuilder
    private var iconView: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - Compatibility Indicator
    
    private var compatibilityIndicator: some View {
        let level = instance.targetAppType.compatibilityLevel
        
        return Image(systemName: level.symbolName)
            .font(.caption2)
            .foregroundStyle(compatibilityColor(for: level))
            .help(instance.targetAppType.displayName)
    }
    
    private func compatibilityColor(for level: CompatibilityLevel) -> Color {
        switch level {
        case .full: return .green
        case .partial: return .yellow
        case .unsupported: return .red
        }
    }
    
    // MARK: - Computed Properties
    
    private var targetAppName: String {
        instance.targetAppPath
            .deletingPathExtension()
            .lastPathComponent
    }
    
    // MARK: - Icon Loading
    
    @MainActor
    private func loadIcon() async {
        // Try to load from shortcut bundle first
        if instance.shortcutExists {
            appIcon = NSWorkspace.shared.icon(forFile: instance.shortcutPath.path)
        } else {
            // Fall back to target app icon
            appIcon = NSWorkspace.shared.icon(forFile: instance.targetAppPath.path)
        }
    }
}

// MARK: - Preview

#Preview {
    let mockInstance = AppInstance(
        name: "Chrome Work",
        application: try! Application(from: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
    )
    
    return InstanceRowView(
        instance: mockInstance,
        viewModel: InstanceViewModel()
    )
    .frame(width: 250)
    .padding()
}
