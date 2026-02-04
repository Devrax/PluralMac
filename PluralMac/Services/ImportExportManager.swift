//
//  ImportExportManager.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import OSLog
import UniformTypeIdentifiers

/// Service for importing and exporting instance configurations.
/// Allows backup and restore of instances without the actual data.
actor ImportExportManager {
    
    // MARK: - Singleton
    
    static let shared = ImportExportManager()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "ImportExportManager")
    private let fileManager = FileManager.default
    
    // MARK: - Export Data Model
    
    /// Represents an exportable instance configuration
    struct ExportedInstance: Codable {
        let version: Int
        let exportDate: Date
        let name: String
        let targetAppPath: String
        let targetBundleIdentifier: String
        let environmentVariables: [String: String]
        let commandLineArguments: [String]
        let isolationMethodOverride: String?
        let eraseDataOnQuit: Bool
        let showMenuBarIcon: Bool
        let notes: String?
        
        init(from instance: AppInstance) {
            self.version = 1
            self.exportDate = Date()
            self.name = instance.name
            self.targetAppPath = instance.targetAppPath.path
            self.targetBundleIdentifier = instance.targetBundleIdentifier
            self.environmentVariables = instance.environmentVariables
            self.commandLineArguments = instance.commandLineArguments
            self.isolationMethodOverride = instance.isolationMethodOverride?.rawValue
            self.eraseDataOnQuit = instance.eraseDataOnQuit
            self.showMenuBarIcon = instance.showMenuBarIcon
            self.notes = instance.notes
        }
    }
    
    /// Represents a collection of exported instances
    struct ExportBundle: Codable {
        let version: Int
        let exportDate: Date
        let appVersion: String
        let instances: [ExportedInstance]
        
        init(instances: [AppInstance]) {
            self.version = 1
            self.exportDate = Date()
            self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            self.instances = instances.map { ExportedInstance(from: $0) }
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Export
    
    /// Export a single instance to JSON data
    /// - Parameter instance: The instance to export
    /// - Returns: JSON data
    func exportInstance(_ instance: AppInstance) throws -> Data {
        let exported = ExportedInstance(from: instance)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        return try encoder.encode(exported)
    }
    
    /// Export multiple instances to JSON data
    /// - Parameter instances: The instances to export
    /// - Returns: JSON data
    func exportInstances(_ instances: [AppInstance]) throws -> Data {
        let bundle = ExportBundle(instances: instances)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        return try encoder.encode(bundle)
    }
    
    /// Export instances to a file
    /// - Parameters:
    ///   - instances: The instances to export
    ///   - destination: The destination file URL
    func exportToFile(_ instances: [AppInstance], destination: URL) throws {
        let data = try exportInstances(instances)
        try data.write(to: destination)
        logger.info("Exported \(instances.count) instances to \(destination.path)")
    }
    
    // MARK: - Import
    
    /// Import instances from JSON data
    /// - Parameter data: The JSON data
    /// - Returns: Array of imported instance configurations
    func importFromData(_ data: Data) throws -> [ImportedInstanceConfig] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // Try to decode as bundle first
        if let bundle = try? decoder.decode(ExportBundle.self, from: data) {
            return try bundle.instances.map { try ImportedInstanceConfig(from: $0) }
        }
        
        // Try single instance
        if let single = try? decoder.decode(ExportedInstance.self, from: data) {
            return [try ImportedInstanceConfig(from: single)]
        }
        
        throw ImportExportError.invalidFormat
    }
    
    /// Import instances from a file
    /// - Parameter url: The source file URL
    /// - Returns: Array of imported instance configurations
    func importFromFile(_ url: URL) throws -> [ImportedInstanceConfig] {
        let data = try Data(contentsOf: url)
        let configs = try importFromData(data)
        logger.info("Imported \(configs.count) instance configs from \(url.path)")
        return configs
    }
    
    /// Validate that target apps exist for imported configs
    /// - Parameter configs: The imported configurations
    /// - Returns: Validation results
    func validateImport(_ configs: [ImportedInstanceConfig]) -> [ImportValidationResult] {
        configs.map { config in
            let appExists = fileManager.fileExists(atPath: config.targetAppPath.path)
            
            var warnings: [String] = []
            if !appExists {
                warnings.append("Target application not found: \(config.targetAppPath.path)")
            }
            
            return ImportValidationResult(
                config: config,
                isValid: appExists,
                warnings: warnings
            )
        }
    }
}

// MARK: - Import Configuration

/// Represents a validated import-ready instance configuration
struct ImportedInstanceConfig {
    let name: String
    let targetAppPath: URL
    let targetBundleIdentifier: String
    let environmentVariables: [String: String]
    let commandLineArguments: [String]
    let isolationMethodOverride: DataIsolationMethod?
    let eraseDataOnQuit: Bool
    let showMenuBarIcon: Bool
    let notes: String?
    
    init(from exported: ImportExportManager.ExportedInstance) throws {
        self.name = exported.name
        self.targetAppPath = URL(fileURLWithPath: exported.targetAppPath)
        self.targetBundleIdentifier = exported.targetBundleIdentifier
        self.environmentVariables = exported.environmentVariables
        self.commandLineArguments = exported.commandLineArguments
        self.isolationMethodOverride = exported.isolationMethodOverride.flatMap { DataIsolationMethod(rawValue: $0) }
        self.eraseDataOnQuit = exported.eraseDataOnQuit
        self.showMenuBarIcon = exported.showMenuBarIcon
        self.notes = exported.notes
    }
    
    /// Create an AppInstance from this config
    func createInstance() throws -> AppInstance {
        let application = try Application(from: targetAppPath)
        var instance = AppInstance(name: name, application: application)
        instance.environmentVariables = environmentVariables
        instance.commandLineArguments = commandLineArguments
        instance.isolationMethodOverride = isolationMethodOverride
        instance.eraseDataOnQuit = eraseDataOnQuit
        instance.showMenuBarIcon = showMenuBarIcon
        instance.notes = notes
        return instance
    }
}

// MARK: - Validation Result

struct ImportValidationResult {
    let config: ImportedInstanceConfig
    let isValid: Bool
    let warnings: [String]
}

// MARK: - Errors

enum ImportExportError: LocalizedError {
    case invalidFormat
    case versionMismatch(expected: Int, found: Int)
    case targetAppNotFound(String)
    case exportFailed(String)
    case importFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid import file format"
        case .versionMismatch(let expected, let found):
            return "Version mismatch: expected \(expected), found \(found)"
        case .targetAppNotFound(let path):
            return "Target application not found: \(path)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        }
    }
}

// MARK: - UTType Extension

extension UTType {
    /// PluralMac instance export file type
    static var pluralMacExport: UTType {
        UTType(exportedAs: "com.mtech.pluralmac.export", conformingTo: .json)
    }
}
