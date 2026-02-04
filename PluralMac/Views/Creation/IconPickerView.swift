//
//  IconPickerView.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// View for selecting and customizing instance icons.
struct IconPickerView: View {
    
    // MARK: - Properties
    
    /// The currently selected/displayed icon
    @Binding var selectedIcon: NSImage?
    
    /// Path to custom icon file (if using custom)
    @Binding var customIconPath: URL?
    
    /// The source app for extracting original icon
    let sourceAppURL: URL?
    
    @State private var isLoading = false
    @State private var showIconOptions = false
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon Preview
            iconPreview
            
            // Action Buttons
            HStack(spacing: 8) {
                Button("Change Icon") {
                    showIconOptions = true
                }
                .buttonStyle(.bordered)
                
                if customIconPath != nil {
                    Button("Reset") {
                        resetToOriginal()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .popover(isPresented: $showIconOptions) {
            iconOptionsPopover
        }
        .task {
            await loadInitialIcon()
        }
    }
    
    // MARK: - Icon Preview
    
    private var iconPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)
                .frame(width: 96, height: 96)
            
            if isLoading {
                ProgressView()
            } else if let icon = selectedIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // MARK: - Icon Options Popover
    
    private var iconOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Icon")
                .font(.headline)
            
            Divider()
            
            // Use original app icon
            Button {
                resetToOriginal()
                showIconOptions = false
            } label: {
                Label("Use Original App Icon", systemImage: "app")
            }
            .buttonStyle(.plain)
            
            // Choose from file
            Button {
                chooseIconFromFile()
                showIconOptions = false
            } label: {
                Label("Choose from File...", systemImage: "folder")
            }
            .buttonStyle(.plain)
            
            // Choose from system icons
            Button {
                chooseSystemIcon()
                showIconOptions = false
            } label: {
                Label("System Icons...", systemImage: "star.square.on.square")
            }
            .buttonStyle(.plain)
            .disabled(true) // TODO: Implement system icon picker
            
            Divider()
            
            // Extract from another app
            Button {
                extractFromAnotherApp()
                showIconOptions = false
            } label: {
                Label("Extract from App...", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 220)
    }
    
    // MARK: - Actions
    
    private func loadInitialIcon() async {
        guard selectedIcon == nil, let appURL = sourceAppURL else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let icon = try await IconExtractor.shared.extractIcon(from: appURL)
            await MainActor.run {
                selectedIcon = icon
            }
        } catch {
            // Fallback to NSWorkspace
            await MainActor.run {
                selectedIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            }
        }
    }
    
    private func resetToOriginal() {
        customIconPath = nil
        
        Task {
            await loadInitialIcon()
        }
    }
    
    private func chooseIconFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .icns, .jpeg, .tiff]
        panel.prompt = "Select"
        panel.message = "Choose an image to use as the icon"
        
        if panel.runModal() == .OK, let url = panel.url {
            customIconPath = url
            
            if let image = NSImage(contentsOf: url) {
                selectedIcon = image
            }
        }
    }
    
    private func chooseSystemIcon() {
        // TODO: Implement SF Symbol picker
    }
    
    private func extractFromAnotherApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Extract Icon"
        panel.message = "Choose an application to extract its icon"
        
        if panel.runModal() == .OK, let appURL = panel.url {
            Task {
                isLoading = true
                defer { isLoading = false }
                
                do {
                    let icon = try await IconExtractor.shared.extractIcon(from: appURL)
                    
                    // Save to temp location
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("png")
                    
                    try IconExtractor.shared.saveAsPNG(image: icon, to: tempURL)
                    
                    await MainActor.run {
                        customIconPath = tempURL
                        selectedIcon = icon
                    }
                } catch {
                    // Handle error
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var icon: NSImage? = nil
    @Previewable @State var customPath: URL? = nil
    
    IconPickerView(
        selectedIcon: $icon,
        customIconPath: $customPath,
        sourceAppURL: URL(fileURLWithPath: "/Applications/Safari.app")
    )
    .padding()
}
