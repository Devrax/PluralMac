//
//  BundleManager.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import OSLog

/// Service responsible for creating, managing, and deleting app instance bundles.
/// Creates standalone .app bundles that wrap target applications with custom
/// environment variables, arguments, and isolated data storage.
actor BundleManager {
    
    // MARK: - Singleton
    
    static let shared = BundleManager()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "BundleManager")
    private let fileManager = FileManager.default
    
    /// Base directory for all PluralMac data
    let baseDirectory: URL
    
    /// Directory where instance bundles are created
    var instancesDirectory: URL {
        baseDirectory.appendingPathComponent("Instances")
    }
    
    /// Directory where isolated data is stored
    var dataDirectory: URL {
        baseDirectory.appendingPathComponent("Data")
    }
    
    /// Directory for cached icons
    var cacheDirectory: URL {
        baseDirectory.appendingPathComponent("Cache")
    }
    
    // MARK: - Initialization
    
    init(baseDirectory: URL = AppInstance.defaultBaseDirectory) {
        self.baseDirectory = baseDirectory
    }
    
    // MARK: - Directory Setup
    
    /// Ensure all required directories exist
    func ensureDirectoriesExist() throws {
        let directories = [
            baseDirectory,
            instancesDirectory,
            dataDirectory,
            cacheDirectory,
            cacheDirectory.appendingPathComponent("Icons")
        ]
        
        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                logger.info("Created directory: \(directory.path)")
            }
        }
    }
    
    // MARK: - Bundle Creation
    
    /// Create an app bundle for the given instance
    /// - Parameter instance: The app instance configuration
    /// - Throws: BundleError if creation fails
    func createBundle(for instance: AppInstance) async throws {
        logger.info("Creating bundle for instance: \(instance.name)")
        
        // Ensure directories exist
        try ensureDirectoriesExist()
        
        // Validate target app still exists
        guard fileManager.fileExists(atPath: instance.targetAppPath.path) else {
            throw BundleError.targetAppNotFound(instance.targetAppPath)
        }
        
        // Remove existing bundle if present
        if fileManager.fileExists(atPath: instance.shortcutPath.path) {
            try fileManager.removeItem(at: instance.shortcutPath)
            logger.debug("Removed existing bundle at: \(instance.shortcutPath.path)")
        }
        
        // Create bundle structure
        try createBundleStructure(for: instance)
        
        // Generate Info.plist
        try createInfoPlist(for: instance)
        
        // Create launcher script
        try createLauncherScript(for: instance)
        
        // Copy or link icon
        try await setupIcon(for: instance)
        
        // Create data directory with symlinks
        try createDataDirectory(for: instance)
        
        // Register with Launch Services
        try registerWithLaunchServices(instance.shortcutPath)
        
        logger.info("Successfully created bundle: \(instance.shortcutPath.path)")
    }
    
    /// Create the bundle directory structure
    private func createBundleStructure(for instance: AppInstance) throws {
        let bundlePath = instance.shortcutPath
        
        // Create Contents directory
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        try fileManager.createDirectory(at: contentsPath, withIntermediateDirectories: true)
        
        // Create MacOS directory (for launcher)
        let macOSPath = contentsPath.appendingPathComponent("MacOS")
        try fileManager.createDirectory(at: macOSPath, withIntermediateDirectories: true)
        
        // Create Resources directory (for icon)
        let resourcesPath = contentsPath.appendingPathComponent("Resources")
        try fileManager.createDirectory(at: resourcesPath, withIntermediateDirectories: true)
        
        logger.debug("Created bundle structure at: \(bundlePath.path)")
    }
    
    /// Generate Info.plist for the bundle
    private func createInfoPlist(for instance: AppInstance) throws {
        let plistPath = instance.shortcutPath
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        
        // Generate unique bundle identifier
        let bundleIdentifier = "com.mtech.PluralMac.instance.\(instance.id.uuidString)"
        
        // Get executable name (sanitized instance name)
        let executableName = sanitizeExecutableName(instance.name)
        
        // Get icon file name
        let iconFileName = "AppIcon"
        
        let plistContents: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": executableName,
            "CFBundleIconFile": iconFileName,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": instance.name,
            "CFBundleDisplayName": instance.name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "12.0",
            "NSHighResolutionCapable": true,
            "LSUIElement": false, // Show in Dock
            
            // Custom keys for PluralMac
            "PluralMacInstanceID": instance.id.uuidString,
            "PluralMacTargetApp": instance.targetAppPath.path,
            "PluralMacTargetBundleID": instance.targetBundleIdentifier
        ]
        
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plistContents,
            format: .xml,
            options: 0
        )
        
        try plistData.write(to: plistPath)
        logger.debug("Created Info.plist at: \(plistPath.path)")
    }
    
    /// Create the launcher shell script
    private func createLauncherScript(for instance: AppInstance) throws {
        let executableName = sanitizeExecutableName(instance.name)
        let launcherPath = instance.shortcutPath
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(executableName)
        
        // Build the launcher script
        var script = """
        #!/bin/bash
        # PluralMac Instance Launcher
        # Instance: \(instance.name)
        # ID: \(instance.id.uuidString)
        # Generated: \(ISO8601DateFormatter().string(from: Date()))
        
        """
        
        // Add environment variables
        let envVars = instance.effectiveEnvironmentVariables
        if !envVars.isEmpty {
            script += "\n# Environment Variables\n"
            for (key, value) in envVars {
                // Escape special characters in value
                let escapedValue = value.replacingOccurrences(of: "\"", with: "\\\"")
                script += "export \(key)=\"\(escapedValue)\"\n"
            }
        }
        
        // Build the exec command
        let targetExecutable = findExecutablePath(for: instance)
        let args = instance.effectiveCommandLineArguments
        
        script += "\n# Launch the target application\n"
        script += "exec \"\(targetExecutable)\""
        
        // Add arguments
        for arg in args {
            let escapedArg = arg.replacingOccurrences(of: "\"", with: "\\\"")
            script += " \"\(escapedArg)\""
        }
        
        // Pass through any additional arguments
        script += " \"$@\"\n"
        
        // Write the script
        try script.write(to: launcherPath, atomically: true, encoding: .utf8)
        
        // Make it executable
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launcherPath.path
        )
        
        logger.debug("Created launcher script at: \(launcherPath.path)")
    }
    
    /// Find the executable path for the target app
    private func findExecutablePath(for instance: AppInstance) -> String {
        // Try to get the executable from the bundle
        if let bundle = Bundle(url: instance.targetAppPath),
           let executableURL = bundle.executableURL {
            return executableURL.path
        }
        
        // Fallback: construct path based on bundle name
        let bundleName = instance.targetAppPath
            .deletingPathExtension()
            .lastPathComponent
        
        return instance.targetAppPath
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(bundleName)
            .path
    }
    
    /// Setup the icon for the bundle
    private func setupIcon(for instance: AppInstance) async throws {
        let resourcesPath = instance.shortcutPath
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
        
        let iconDestination = resourcesPath.appendingPathComponent("AppIcon.icns")
        
        if let customIconPath = instance.customIconPath,
           fileManager.fileExists(atPath: customIconPath.path) {
            // Handle custom icon based on its type
            let pathExtension = customIconPath.pathExtension.lowercased()
            
            if pathExtension == "icns" {
                // Already ICNS, just copy
                try fileManager.copyItem(at: customIconPath, to: iconDestination)
            } else {
                // Convert to ICNS using IconExtractor
                let customImage = try await IconExtractor.shared.loadCustomIcon(from: customIconPath)
                try await IconExtractor.shared.saveAsICNS(image: customImage, to: iconDestination)
            }
            logger.debug("Copied custom icon to bundle")
        } else {
            // Extract icon from target app using IconExtractor
            try await extractAndCopyIcon(
                from: instance.targetAppPath,
                to: iconDestination
            )
        }
    }
    
    /// Extract icon from source app and copy to destination
    private func extractAndCopyIcon(from appPath: URL, to destination: URL) async throws {
        // Use IconExtractor for proper icon extraction and ICNS generation
        do {
            let icon = try await IconExtractor.shared.extractIcon(from: appPath, size: 512)
            try await IconExtractor.shared.saveAsICNS(image: icon, to: destination)
            logger.debug("Extracted and saved icon using IconExtractor")
        } catch {
            // Fallback: try to copy existing ICNS directly
            try await fallbackIconCopy(from: appPath, to: destination)
        }
    }
    
    /// Fallback method to copy icon directly from bundle
    private func fallbackIconCopy(from appPath: URL, to destination: URL) async throws {
        guard let bundle = Bundle(url: appPath) else {
            throw BundleError.invalidTargetBundle(appPath)
        }
        
        // Check for CFBundleIconFile
        if let iconFileName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            var iconName = iconFileName
            if !iconName.hasSuffix(".icns") {
                iconName += ".icns"
            }
            
            let potentialPath = appPath
                .appendingPathComponent("Contents")
                .appendingPathComponent("Resources")
                .appendingPathComponent(iconName)
            
            if fileManager.fileExists(atPath: potentialPath.path) {
                try fileManager.copyItem(at: potentialPath, to: destination)
                logger.debug("Copied icon directly from bundle")
                return
            }
        }
        
        // Ultimate fallback: use NSWorkspace
        try await MainActor.run {
            let workspace = NSWorkspace.shared
            let icon = workspace.icon(forFile: appPath.path)
            
            guard let tiffData = icon.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw BundleError.iconExtractionFailed(appPath)
            }
            
            // Save as PNG temporarily
            let pngDestination = destination.deletingPathExtension().appendingPathExtension("png")
            try pngData.write(to: pngDestination)
            
            // Rename to .icns
            try self.fileManager.moveItem(at: pngDestination, to: destination)
            
            logger.debug("Extracted icon using NSWorkspace fallback")
        }
    }
    
    /// Create the data directory with required symlinks
    private func createDataDirectory(for instance: AppInstance) throws {
        let dataPath = instance.dataPath
        
        // Create the data directory if it doesn't exist
        if !fileManager.fileExists(atPath: dataPath.path) {
            try fileManager.createDirectory(
                at: dataPath,
                withIntermediateDirectories: true
            )
        }
        
        // Only create symlinks if using HOME redirection
        guard instance.effectiveIsolationMethod == .homeRedirection else {
            return
        }
        
        // Create essential symlinks to the real user directories
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let symlinks: [(String, String)] = [
            // User folders - link to real locations
            ("Desktop", "Desktop"),
            ("Documents", "Documents"),
            ("Downloads", "Downloads"),
            ("Movies", "Movies"),
            ("Music", "Music"),
            ("Pictures", "Pictures"),
            ("Public", "Public"),
            
            // Essential Library items
            ("Library/Keychains", "Library/Keychains"),
            ("Library/Preferences/com.apple.security.plist", "Library/Preferences/com.apple.security.plist"),
        ]
        
        for (relativePath, targetRelativePath) in symlinks {
            let linkPath = dataPath.appendingPathComponent(relativePath)
            let targetPath = homeDirectory.appendingPathComponent(targetRelativePath)
            
            // Create parent directory if needed
            let parentDir = linkPath.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDir.path) {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            
            // Only create symlink if target exists and link doesn't
            if fileManager.fileExists(atPath: targetPath.path) &&
               !fileManager.fileExists(atPath: linkPath.path) {
                try fileManager.createSymbolicLink(at: linkPath, withDestinationURL: targetPath)
                logger.debug("Created symlink: \(relativePath) -> \(targetPath.path)")
            }
        }
        
        // Create Library directory structure for the instance
        let libraryPaths = [
            "Library",
            "Library/Application Support",
            "Library/Caches",
            "Library/Preferences",
            "Library/Logs"
        ]
        
        for path in libraryPaths {
            let fullPath = dataPath.appendingPathComponent(path)
            if !fileManager.fileExists(atPath: fullPath.path) {
                try fileManager.createDirectory(at: fullPath, withIntermediateDirectories: true)
            }
        }
        
        logger.debug("Created data directory with symlinks at: \(dataPath.path)")
    }
    
    /// Register the bundle with Launch Services
    private func registerWithLaunchServices(_ bundlePath: URL) throws {
        // Use LSRegisterURL to register the app with Launch Services
        let status = LSRegisterURL(bundlePath as CFURL, true)
        
        if status != noErr {
            logger.warning("LSRegisterURL returned status: \(status)")
            // Not throwing here as this is not critical
        } else {
            logger.debug("Registered bundle with Launch Services")
        }
    }
    
    // MARK: - Bundle Deletion
    
    /// Delete an app bundle and optionally its data
    /// - Parameters:
    ///   - instance: The app instance to delete
    ///   - deleteData: Whether to also delete the isolated data directory
    func deleteBundle(for instance: AppInstance, deleteData: Bool = false) throws {
        logger.info("Deleting bundle for instance: \(instance.name)")
        
        // Delete the bundle
        if fileManager.fileExists(atPath: instance.shortcutPath.path) {
            try fileManager.removeItem(at: instance.shortcutPath)
            logger.debug("Deleted bundle at: \(instance.shortcutPath.path)")
        }
        
        // Optionally delete data
        if deleteData && fileManager.fileExists(atPath: instance.dataPath.path) {
            try fileManager.removeItem(at: instance.dataPath)
            logger.debug("Deleted data at: \(instance.dataPath.path)")
        }
        
        // Unregister from Launch Services (best effort)
        // Note: There's no direct API to unregister, but removing the bundle
        // and calling LSRegisterURL on the parent directory can help
        
        logger.info("Successfully deleted bundle for: \(instance.name)")
    }
    
    // MARK: - Bundle Update
    
    /// Update an existing bundle (regenerate launcher, update icon, etc.)
    func updateBundle(for instance: AppInstance) async throws {
        logger.info("Updating bundle for instance: \(instance.name)")
        
        // Validate bundle exists
        guard fileManager.fileExists(atPath: instance.shortcutPath.path) else {
            // Bundle doesn't exist, create it
            try await createBundle(for: instance)
            return
        }
        
        // Update Info.plist
        try createInfoPlist(for: instance)
        
        // Update launcher script
        try createLauncherScript(for: instance)
        
        // Update icon if custom icon changed
        try await setupIcon(for: instance)
        
        // Re-register with Launch Services
        try registerWithLaunchServices(instance.shortcutPath)
        
        logger.info("Successfully updated bundle: \(instance.name)")
    }
    
    // MARK: - Helpers
    
    /// Sanitize a name to be used as an executable name
    private func sanitizeExecutableName(_ name: String) -> String {
        let invalidCharacters = CharacterSet.alphanumerics.inverted
        let sanitized = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        
        return sanitized.isEmpty ? "Launcher" : sanitized
    }
    
    /// Check if a bundle exists for the given instance
    func bundleExists(for instance: AppInstance) -> Bool {
        fileManager.fileExists(atPath: instance.shortcutPath.path)
    }
    
    /// Get the size of an instance's data directory
    func dataDirectorySize(for instance: AppInstance) throws -> Int64 {
        guard fileManager.fileExists(atPath: instance.dataPath.path) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(
            at: instance.dataPath,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if resourceValues.isDirectory == false {
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }
            }
        }
        
        return totalSize
    }
}

// MARK: - Errors

/// Errors that can occur during bundle operations
enum BundleError: LocalizedError {
    case targetAppNotFound(URL)
    case invalidTargetBundle(URL)
    case iconExtractionFailed(URL)
    case bundleCreationFailed(String)
    case launcherCreationFailed(String)
    case permissionDenied(URL)
    
    var errorDescription: String? {
        switch self {
        case .targetAppNotFound(let url):
            return "Target application not found at: \(url.path)"
        case .invalidTargetBundle(let url):
            return "Invalid application bundle at: \(url.path)"
        case .iconExtractionFailed(let url):
            return "Failed to extract icon from: \(url.path)"
        case .bundleCreationFailed(let message):
            return "Failed to create bundle: \(message)"
        case .launcherCreationFailed(let message):
            return "Failed to create launcher: \(message)"
        case .permissionDenied(let url):
            return "Permission denied for: \(url.path)"
        }
    }
}

// MARK: - Launch Services Import

import CoreServices
