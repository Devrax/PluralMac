//
//  AppInstance.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation

/// Represents a configured instance of an application with isolated data storage.
/// Each instance can have its own environment variables, command-line arguments,
/// custom icon, and data directory.
struct AppInstance: Identifiable, Codable, Hashable, Sendable {
    
    // MARK: - Properties
    
    /// Unique identifier for this instance
    let id: UUID
    
    /// User-defined display name for this instance
    var name: String
    
    /// Bundle identifier of the target application
    let targetBundleIdentifier: String
    
    /// Path to the original target application
    let targetAppPath: URL
    
    /// Type of the target application (for data isolation strategy)
    let targetAppType: AppType
    
    /// Path to the created shortcut bundle
    /// `~/Library/PluralMac/Instances/{name}.app`
    var shortcutPath: URL
    
    /// Path to the isolated data directory for this instance
    /// `~/Library/PluralMac/Data/{id}/`
    var dataPath: URL
    
    /// Custom environment variables for this instance
    var environmentVariables: [String: String]
    
    /// Custom command-line arguments for this instance
    var commandLineArguments: [String]
    
    /// Path to custom icon (nil = use original app icon)
    var customIconPath: URL?
    
    /// Data isolation method override (nil = use default for app type)
    var isolationMethodOverride: DataIsolationMethod?
    
    /// Whether to erase data when the shortcut quits (for labs/education)
    var eraseDataOnQuit: Bool
    
    /// Whether to show a menu bar icon when running
    var showMenuBarIcon: Bool
    
    /// Optional notes/description for this instance
    var notes: String?
    
    /// Creation date
    let createdAt: Date
    
    /// Last modification date
    var modifiedAt: Date
    
    /// Last launch date (nil if never launched)
    var lastLaunchedAt: Date?
    
    // MARK: - Initialization
    
    /// Create a new app instance configuration
    /// - Parameters:
    ///   - name: Display name for the instance
    ///   - application: The target application to create an instance of
    ///   - baseDirectory: Base directory for PluralMac data (default: ~/Library/PluralMac)
    init(
        name: String,
        application: Application,
        baseDirectory: URL = Self.defaultBaseDirectory
    ) {
        self.id = UUID()
        self.name = name
        self.targetBundleIdentifier = application.bundleIdentifier
        self.targetAppPath = application.path
        self.targetAppType = application.appType
        
        // Generate paths
        let sanitizedName = Self.sanitizeFileName(name)
        self.shortcutPath = baseDirectory
            .appendingPathComponent("Instances")
            .appendingPathComponent("\(sanitizedName).app")
        
        self.dataPath = baseDirectory
            .appendingPathComponent("Data")
            .appendingPathComponent(id.uuidString)
        
        // Defaults
        self.environmentVariables = [:]
        self.commandLineArguments = []
        self.customIconPath = nil
        self.isolationMethodOverride = nil
        self.eraseDataOnQuit = false
        self.showMenuBarIcon = false
        self.notes = nil
        
        // Timestamps
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.lastLaunchedAt = nil
    }
    
    // MARK: - Computed Properties
    
    /// The effective data isolation method (override or default for app type)
    var effectiveIsolationMethod: DataIsolationMethod {
        isolationMethodOverride ?? targetAppType.isolationMethod
    }
    
    /// Check if the shortcut bundle exists
    var shortcutExists: Bool {
        FileManager.default.fileExists(atPath: shortcutPath.path)
    }
    
    /// Check if the data directory exists
    var dataDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: dataPath.path)
    }
    
    /// Get the complete environment variables including HOME override if needed
    var effectiveEnvironmentVariables: [String: String] {
        var env = environmentVariables
        
        // Always redirect HOME for complete isolation
        // This ensures apps that hardcode paths still work
        env["HOME"] = dataPath.path
        
        // Also set XDG directories for apps that use them
        env["XDG_CONFIG_HOME"] = dataPath.appendingPathComponent(".config").path
        env["XDG_DATA_HOME"] = dataPath.appendingPathComponent(".local/share").path
        env["XDG_CACHE_HOME"] = dataPath.appendingPathComponent(".cache").path
        
        return env
    }
    
    /// Get the complete command-line arguments including data isolation args
    var effectiveCommandLineArguments: [String] {
        var args = commandLineArguments
        
        // Check for app-specific arguments first
        let bundleId = targetBundleIdentifier.lowercased()
        
        // Spotify uses --mu for multiple instances
        if bundleId.contains("spotify") {
            args.append("--mu=\(id.uuidString)")
            return args
        }
        
        // Discord uses --multi-instance
        if bundleId.contains("discord") {
            args.append("--multi-instance")
            // Discord also needs a separate user data dir
            args.append("--user-data-dir=\(dataPath.path)")
            return args
        }
        
        // Slack uses --user-data-dir
        if bundleId.contains("slack") {
            args.append("--user-data-dir=\(dataPath.path)")
            return args
        }
        
        // Default behavior based on isolation method
        switch effectiveIsolationMethod {
        case .userDataDir:
            args.append("--user-data-dir=\(dataPath.path)")
        case .profileArgument:
            args.append(contentsOf: ["-profile", dataPath.path])
        case .homeRedirection, .none:
            break
        }
        
        return args
    }
    
    /// Default base directory for PluralMac data
    static var defaultBaseDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("PluralMac")
    }
    
    // MARK: - Methods
    
    /// Update the modification timestamp
    mutating func touch() {
        modifiedAt = Date()
    }
    
    /// Record that the instance was launched
    mutating func recordLaunch() {
        lastLaunchedAt = Date()
        touch()
    }
    
    /// Rename the instance (updates name and shortcut path)
    mutating func rename(to newName: String, baseDirectory: URL = Self.defaultBaseDirectory) {
        name = newName
        let sanitizedName = Self.sanitizeFileName(newName)
        shortcutPath = baseDirectory
            .appendingPathComponent("Instances")
            .appendingPathComponent("\(sanitizedName).app")
        touch()
    }
    
    /// Set a custom environment variable
    mutating func setEnvironmentVariable(_ key: String, value: String) {
        environmentVariables[key] = value
        touch()
    }
    
    /// Remove an environment variable
    mutating func removeEnvironmentVariable(_ key: String) {
        environmentVariables.removeValue(forKey: key)
        touch()
    }
    
    /// Add a command-line argument
    mutating func addArgument(_ argument: String) {
        if !commandLineArguments.contains(argument) {
            commandLineArguments.append(argument)
            touch()
        }
    }
    
    /// Remove a command-line argument
    mutating func removeArgument(_ argument: String) {
        commandLineArguments.removeAll { $0 == argument }
        touch()
    }
    
    // MARK: - Private Helpers
    
    /// Sanitize a string to be used as a file name
    private static func sanitizeFileName(_ name: String) -> String {
        // Remove/replace characters that are problematic in file names
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let sanitized = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure non-empty
        return sanitized.isEmpty ? "Instance" : sanitized
    }
}

// MARK: - Codable Conformance

extension AppInstance {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case targetBundleIdentifier
        case targetAppPath
        case targetAppType
        case shortcutPath
        case dataPath
        case environmentVariables
        case commandLineArguments
        case customIconPath
        case isolationMethodOverride
        case eraseDataOnQuit
        case showMenuBarIcon
        case createdAt
        case modifiedAt
        case lastLaunchedAt
    }
}

// MARK: - Display Helpers

extension AppInstance {
    /// Formatted creation date string
    var createdAtFormatted: String {
        Self.dateFormatter.string(from: createdAt)
    }
    
    /// Formatted last launch date string
    var lastLaunchedAtFormatted: String? {
        guard let date = lastLaunchedAt else { return nil }
        return Self.dateFormatter.string(from: date)
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
