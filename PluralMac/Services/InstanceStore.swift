//
//  InstanceStore.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import OSLog

/// Persistent storage for app instances using JSON file storage.
actor InstanceStore {
    
    // MARK: - Singleton
    
    static let shared = InstanceStore()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "InstanceStore")
    private let fileManager = FileManager.default
    
    /// URL to the instances JSON file
    private var storeURL: URL {
        AppInstance.defaultBaseDirectory
            .appendingPathComponent("instances.json")
    }
    
    /// In-memory cache of instances
    private var cachedInstances: [AppInstance]?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - CRUD Operations
    
    /// Load all instances from storage
    func loadInstances() async throws -> [AppInstance] {
        // Return cached if available
        if let cached = cachedInstances {
            return cached
        }
        
        // Ensure base directory exists
        let baseDir = AppInstance.defaultBaseDirectory
        if !fileManager.fileExists(atPath: baseDir.path) {
            try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        
        // Check if file exists
        guard fileManager.fileExists(atPath: storeURL.path) else {
            logger.info("No instances file found, returning empty array")
            cachedInstances = []
            return []
        }
        
        // Load and decode
        let data = try Data(contentsOf: storeURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let instances = try decoder.decode([AppInstance].self, from: data)
        cachedInstances = instances
        
        logger.info("Loaded \(instances.count) instances from storage")
        return instances
    }
    
    /// Save all instances to storage
    func saveInstances(_ instances: [AppInstance]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(instances)
        
        // Ensure directory exists
        let directory = storeURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        try data.write(to: storeURL, options: .atomic)
        cachedInstances = instances
        
        logger.info("Saved \(instances.count) instances to storage")
    }
    
    /// Add a new instance
    func addInstance(_ instance: AppInstance) async throws {
        var instances = try await loadInstances()
        instances.append(instance)
        try await saveInstances(instances)
        logger.info("Added instance: \(instance.name)")
    }
    
    /// Update an existing instance
    func updateInstance(_ instance: AppInstance) async throws {
        var instances = try await loadInstances()
        
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else {
            throw StoreError.instanceNotFound(instance.id)
        }
        
        instances[index] = instance
        try await saveInstances(instances)
        logger.info("Updated instance: \(instance.name)")
    }
    
    /// Delete an instance by ID
    func deleteInstance(id: UUID) async throws {
        var instances = try await loadInstances()
        
        guard let index = instances.firstIndex(where: { $0.id == id }) else {
            throw StoreError.instanceNotFound(id)
        }
        
        let removed = instances.remove(at: index)
        try await saveInstances(instances)
        logger.info("Deleted instance: \(removed.name)")
    }
    
    /// Get a specific instance by ID
    func getInstance(id: UUID) async throws -> AppInstance? {
        let instances = try await loadInstances()
        return instances.first { $0.id == id }
    }
    
    /// Clear the cache to force reload from disk
    func clearCache() {
        cachedInstances = nil
        logger.debug("Cache cleared")
    }
}

// MARK: - Errors

enum StoreError: LocalizedError {
    case instanceNotFound(UUID)
    case saveFailed(Error)
    case loadFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .instanceNotFound(let id):
            return "Instance not found: \(id)"
        case .saveFailed(let error):
            return "Failed to save instances: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load instances: \(error.localizedDescription)"
        }
    }
}
