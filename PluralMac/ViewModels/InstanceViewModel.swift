//
//  InstanceViewModel.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import SwiftUI
import OSLog

/// ViewModel for managing the list of app instances.
/// Handles loading, creating, updating, deleting, and launching instances.
@MainActor
@Observable
final class InstanceViewModel {
    
    // MARK: - Properties
    
    /// All app instances
    var instances: [AppInstance] = []
    
    /// Currently selected instance (for detail view)
    var selectedInstance: AppInstance?
    
    /// Search/filter text
    var searchText: String = ""
    
    /// Loading state
    var isLoading: Bool = false
    
    /// Error message to display
    var errorMessage: String?
    
    /// Whether to show error alert
    var showError: Bool = false
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "InstanceViewModel")
    private let store = InstanceStore.shared
    private let bundleManager = BundleManager.shared
    
    // MARK: - Computed Properties
    
    /// Filtered instances based on search text
    var filteredInstances: [AppInstance] {
        guard !searchText.isEmpty else { return instances }
        
        let lowercasedSearch = searchText.lowercased()
        return instances.filter { instance in
            instance.name.lowercased().contains(lowercasedSearch) ||
            instance.targetBundleIdentifier.lowercased().contains(lowercasedSearch)
        }
    }
    
    /// Whether there are any instances
    var hasInstances: Bool {
        !instances.isEmpty
    }
    
    /// Number of instances
    var instanceCount: Int {
        instances.count
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Data Loading
    
    /// Load instances from storage
    func loadInstances() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            instances = try await store.loadInstances()
            logger.info("Loaded \(self.instances.count) instances")
        } catch {
            handleError(error, context: "loading instances")
        }
    }
    
    /// Refresh instances from storage
    func refreshInstances() async {
        await store.clearCache()
        await loadInstances()
    }
    
    // MARK: - Instance Creation
    
    /// Create a new instance from an application
    /// - Parameters:
    ///   - name: Display name for the instance
    ///   - application: Target application
    ///   - environmentVariables: Custom environment variables
    ///   - arguments: Custom command-line arguments
    ///   - customIconPath: Optional custom icon
    /// - Returns: The created instance
    @discardableResult
    func createInstance(
        name: String,
        application: Application,
        environmentVariables: [String: String] = [:],
        arguments: [String] = [],
        customIconPath: URL? = nil
    ) async throws -> AppInstance {
        logger.info("Creating instance: \(name) for \(application.name)")
        
        // Create the instance model
        var instance = AppInstance(name: name, application: application)
        instance.environmentVariables = environmentVariables
        instance.commandLineArguments = arguments
        instance.customIconPath = customIconPath
        
        // Create the bundle
        try await bundleManager.createBundle(for: instance)
        
        // Save to storage
        try await store.addInstance(instance)
        
        // Update local list
        instances.append(instance)
        
        logger.info("Successfully created instance: \(name)")
        return instance
    }
    
    // MARK: - Instance Updates
    
    /// Update an existing instance
    func updateInstance(_ instance: AppInstance) async throws {
        logger.info("Updating instance: \(instance.name)")
        
        // Update the bundle
        try await bundleManager.updateBundle(for: instance)
        
        // Update storage
        try await store.updateInstance(instance)
        
        // Update local list
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        }
        
        // Update selection if needed
        if selectedInstance?.id == instance.id {
            selectedInstance = instance
        }
        
        logger.info("Successfully updated instance: \(instance.name)")
    }
    
    /// Rename an instance
    func renameInstance(_ instance: AppInstance, to newName: String) async throws {
        var updated = instance
        updated.rename(to: newName)
        
        // Need to recreate bundle with new name
        try await bundleManager.deleteBundle(for: instance, deleteData: false)
        try await bundleManager.createBundle(for: updated)
        
        try await store.updateInstance(updated)
        
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = updated
        }
        
        if selectedInstance?.id == instance.id {
            selectedInstance = updated
        }
    }
    
    // MARK: - Instance Deletion
    
    /// Delete an instance
    /// - Parameters:
    ///   - instance: The instance to delete
    ///   - deleteData: Whether to also delete isolated data
    func deleteInstance(_ instance: AppInstance, deleteData: Bool = false) async throws {
        logger.info("Deleting instance: \(instance.name), deleteData: \(deleteData)")
        
        // Delete the bundle
        try await bundleManager.deleteBundle(for: instance, deleteData: deleteData)
        
        // Remove from storage
        try await store.deleteInstance(id: instance.id)
        
        // Update local list
        instances.removeAll { $0.id == instance.id }
        
        // Clear selection if deleted
        if selectedInstance?.id == instance.id {
            selectedInstance = nil
        }
        
        logger.info("Successfully deleted instance: \(instance.name)")
    }
    
    /// Delete multiple instances
    func deleteInstances(_ instances: [AppInstance], deleteData: Bool = false) async throws {
        for instance in instances {
            try await deleteInstance(instance, deleteData: deleteData)
        }
    }
    
    // MARK: - Instance Launching
    
    /// Launch an instance
    func launchInstance(_ instance: AppInstance) async throws {
        logger.info("Launching instance: \(instance.name)")
        
        // Ensure bundle exists
        let bundleExists = await bundleManager.bundleExists(for: instance)
        if !bundleExists {
            logger.warning("Bundle doesn't exist, recreating...")
            try await bundleManager.createBundle(for: instance)
        }
        
        // Launch the app
        _ = try await LaunchServicesHelper.launchAsync(instance.shortcutPath)
        
        // Update last launched timestamp
        var updated = instance
        updated.recordLaunch()
        try await store.updateInstance(updated)
        
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = updated
        }
        
        logger.info("Successfully launched instance: \(instance.name)")
    }
    
    // MARK: - Finder Integration
    
    /// Reveal instance shortcut in Finder
    func revealInFinder(_ instance: AppInstance) {
        LaunchServicesHelper.revealInFinder(instance.shortcutPath)
    }
    
    /// Reveal instance data directory in Finder
    func revealDataInFinder(_ instance: AppInstance) {
        LaunchServicesHelper.revealInFinder(instance.dataPath)
    }
    
    // MARK: - Duplicate
    
    /// Duplicate an instance with a new name
    func duplicateInstance(_ instance: AppInstance, newName: String) async throws -> AppInstance {
        logger.info("Duplicating instance: \(instance.name) as \(newName)")
        
        // Load the original application
        let application = try Application(from: instance.targetAppPath)
        
        // Create new instance with same settings
        var newInstance = AppInstance(name: newName, application: application)
        newInstance.environmentVariables = instance.environmentVariables
        newInstance.commandLineArguments = instance.commandLineArguments
        newInstance.customIconPath = instance.customIconPath
        newInstance.isolationMethodOverride = instance.isolationMethodOverride
        newInstance.eraseDataOnQuit = instance.eraseDataOnQuit
        newInstance.showMenuBarIcon = instance.showMenuBarIcon
        
        // Create the bundle
        try await bundleManager.createBundle(for: newInstance)
        
        // Save to storage
        try await store.addInstance(newInstance)
        
        // Update local list
        instances.append(newInstance)
        
        return newInstance
    }
    
    // MARK: - Import/Export
    
    /// Export selected instances to a file
    func exportInstances(_ instancesToExport: [AppInstance], to url: URL) async throws {
        logger.info("Exporting \(instancesToExport.count) instances")
        try await ImportExportManager.shared.exportToFile(instancesToExport, destination: url)
        logger.info("Successfully exported instances to \(url.path)")
    }
    
    /// Export all instances to a file
    func exportAllInstances(to url: URL) async throws {
        try await exportInstances(instances, to: url)
    }
    
    /// Import instances from a file
    /// - Parameter url: The file to import from
    /// - Returns: Array of validation results
    func importInstances(from url: URL) async throws -> [ImportValidationResult] {
        logger.info("Importing instances from \(url.path)")
        
        let configs = try await ImportExportManager.shared.importFromFile(url)
        let validationResults = await ImportExportManager.shared.validateImport(configs)
        
        return validationResults
    }
    
    /// Create instances from validated import configs
    func createFromImport(_ configs: [ImportedInstanceConfig]) async throws {
        for config in configs {
            do {
                var instance = try config.createInstance()
                
                // Create the bundle
                try await bundleManager.createBundle(for: instance)
                
                // Save to storage
                try await store.addInstance(instance)
                
                // Update local list
                instances.append(instance)
                
                logger.info("Imported instance: \(instance.name)")
            } catch {
                logger.error("Failed to import \(config.name): \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error, context: String) {
        logger.error("Error \(context): \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        showError = true
    }
    
    /// Clear the current error
    func clearError() {
        errorMessage = nil
        showError = false
    }
}

// MARK: - Selection Helpers

extension InstanceViewModel {
    
    /// Select an instance
    func select(_ instance: AppInstance?) {
        selectedInstance = instance
    }
    
    /// Check if an instance is selected
    func isSelected(_ instance: AppInstance) -> Bool {
        selectedInstance?.id == instance.id
    }
    
    /// Select the first instance if none selected
    func selectFirstIfNeeded() {
        if selectedInstance == nil, let first = filteredInstances.first {
            selectedInstance = first
        }
    }
}
