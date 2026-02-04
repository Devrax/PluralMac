//
//  CompatibilityDatabase.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import OSLog

/// Service that provides compatibility information for applications.
/// Loads data from the bundled compatibility.json file.
actor CompatibilityDatabase {
    
    // MARK: - Singleton
    
    static let shared = CompatibilityDatabase()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "CompatibilityDatabase")
    private var entries: [String: CompatibilityEntry] = [:]
    private var isLoaded = false
    
    // MARK: - Models
    
    struct CompatibilityEntry: Codable {
        let bundleIdentifier: String
        let name: String
        let appType: String
        let compatibilityLevel: String
        let isolationMethod: String
        let recommendedArguments: [String]
        let notes: String
        let testedVersion: String
        
        var appTypeEnum: AppType {
            switch appType {
            case "chromiumBased": return .chromiumBased
            case "firefoxBased": return .firefoxBased
            case "electronBased": return .electronBased
            case "toDesktop": return .toDesktop
            case "sandboxed": return .sandboxed
            case "system": return .system
            default: return .generic
            }
        }
        
        var compatibilityLevelEnum: CompatibilityLevel {
            switch compatibilityLevel {
            case "full": return .full
            case "partial": return .partial
            case "unsupported": return .unsupported
            default: return .partial
            }
        }
        
        var isolationMethodEnum: DataIsolationMethod {
            switch isolationMethod {
            case "userDataDir": return .userDataDir
            case "profile": return .profile
            case "homeRedirection": return .homeRedirection
            case "none": return .none
            default: return .homeRedirection
            }
        }
    }
    
    private struct DatabaseFile: Codable {
        let version: Int
        let lastUpdated: String
        let applications: [CompatibilityEntry]
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Loading
    
    /// Load the compatibility database from the bundle
    func load() async {
        guard !isLoaded else { return }
        
        guard let url = Bundle.main.url(forResource: "compatibility", withExtension: "json") else {
            logger.warning("Compatibility database not found in bundle")
            isLoaded = true
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let database = try JSONDecoder().decode(DatabaseFile.self, from: data)
            
            // Index by bundle identifier
            entries = Dictionary(
                uniqueKeysWithValues: database.applications.map { ($0.bundleIdentifier.lowercased(), $0) }
            )
            
            isLoaded = true
            logger.info("Loaded compatibility database with \(database.applications.count) entries")
        } catch {
            logger.error("Failed to load compatibility database: \(error.localizedDescription)")
            isLoaded = true
        }
    }
    
    // MARK: - Queries
    
    /// Get compatibility entry for a bundle identifier
    /// - Parameter bundleId: The bundle identifier to look up
    /// - Returns: Compatibility entry if found
    func entry(for bundleId: String) async -> CompatibilityEntry? {
        await load()
        return entries[bundleId.lowercased()]
    }
    
    /// Check if an app is in the database
    /// - Parameter bundleId: The bundle identifier to check
    /// - Returns: True if the app is in the database
    func isKnown(bundleId: String) async -> Bool {
        await entry(for: bundleId) != nil
    }
    
    /// Get compatibility level for an app
    /// - Parameter bundleId: The bundle identifier
    /// - Returns: Compatibility level (defaults to partial if unknown)
    func compatibilityLevel(for bundleId: String) async -> CompatibilityLevel {
        if let entry = await entry(for: bundleId) {
            return entry.compatibilityLevelEnum
        }
        return .partial
    }
    
    /// Get recommended settings for an app
    /// - Parameter bundleId: The bundle identifier
    /// - Returns: Tuple of app type, isolation method, and arguments
    func recommendedSettings(for bundleId: String) async -> (AppType, DataIsolationMethod, [String])? {
        guard let entry = await entry(for: bundleId) else { return nil }
        
        return (
            entry.appTypeEnum,
            entry.isolationMethodEnum,
            entry.recommendedArguments
        )
    }
    
    /// Get all known apps of a specific type
    /// - Parameter type: The app type to filter by
    /// - Returns: Array of matching entries
    func apps(ofType type: AppType) async -> [CompatibilityEntry] {
        await load()
        return entries.values.filter { $0.appTypeEnum == type }
    }
    
    /// Get all fully compatible apps
    func fullyCompatibleApps() async -> [CompatibilityEntry] {
        await load()
        return entries.values.filter { $0.compatibilityLevelEnum == .full }
    }
    
    /// Get compatibility notes for an app
    /// - Parameter bundleId: The bundle identifier
    /// - Returns: Notes string if available
    func notes(for bundleId: String) async -> String? {
        await entry(for: bundleId)?.notes
    }
}

// MARK: - Application Extension

extension Application {
    
    /// Check compatibility using the database
    func checkCompatibility() async -> (level: CompatibilityLevel, notes: String?) {
        let db = CompatibilityDatabase.shared
        
        if let entry = await db.entry(for: bundleIdentifier) {
            return (entry.compatibilityLevelEnum, entry.notes)
        }
        
        // Fall back to detection-based compatibility
        return (appType.compatibilityLevel, nil)
    }
}
