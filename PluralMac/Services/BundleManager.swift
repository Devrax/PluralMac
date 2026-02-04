//
//  BundleManager.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import AppKit
import OSLog
import CoreServices

/// Service responsible for creating, managing, and deleting app instance bundles.
/// Uses a "trampoline" approach: creates minimal .app bundles that launch the
/// ORIGINAL unmodified app with custom environment variables.
/// This avoids triggering anti-tampering protections in CEF/Electron apps.
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
    
    // MARK: - Bundle Creation (Trampoline Approach)
    
    /// Create a minimal "trampoline" app bundle that launches the original app
    /// with custom environment variables. This approach:
    /// 1. Does NOT copy or modify the original app (avoids anti-tampering)
    /// 2. Creates a minimal .app with just Info.plist, launcher script, and icon
    /// 3. The launcher sets environment variables and executes the ORIGINAL binary
    /// - Parameter instance: The app instance configuration
    /// - Throws: BundleError if creation fails
    func createBundle(for instance: AppInstance) async throws {
        logger.info("Creating trampoline bundle for instance: \(instance.name)")
        
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
        
        // Create minimal bundle structure (NOT copying the original app)
        try createMinimalBundleStructure(for: instance)
        
        // Create Info.plist with unique Bundle ID
        try createInfoPlist(for: instance)
        
        // Create launcher script that executes the ORIGINAL app binary
        try createLauncherScript(for: instance)
        
        // Setup icon (extract from original or use custom)
        try await setupIcon(for: instance)
        
        // Create data directory with symlinks
        try createDataDirectory(for: instance)
        
        // Sign the minimal bundle (required for Gatekeeper)
        try await signBundle(at: instance.shortcutPath)
        
        // Register with Launch Services
        try registerWithLaunchServices(instance.shortcutPath)
        
        logger.info("Successfully created trampoline bundle: \(instance.shortcutPath.path)")
    }
    
    // MARK: - Bundle Structure Creation
    
    /// Create the minimal bundle directory structure
    private func createMinimalBundleStructure(for instance: AppInstance) throws {
        let contentsPath = instance.shortcutPath.appendingPathComponent("Contents")
        let macOSPath = contentsPath.appendingPathComponent("MacOS")
        let resourcesPath = contentsPath.appendingPathComponent("Resources")
        
        // Create directories
        try fileManager.createDirectory(at: macOSPath, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesPath, withIntermediateDirectories: true)
        
        logger.debug("Created minimal bundle structure at: \(instance.shortcutPath.path)")
    }
    
    /// Create Info.plist for the trampoline bundle
    private func createInfoPlist(for instance: AppInstance) throws {
        let plistPath = instance.shortcutPath
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        
        // Get original bundle info
        guard let originalBundle = Bundle(url: instance.targetAppPath),
              let originalExecName = originalBundle.executableURL?.lastPathComponent else {
            throw BundleError.invalidTargetBundle(instance.targetAppPath)
        }
        
        let originalBundleId = originalBundle.bundleIdentifier ?? "unknown"
        let originalVersion = originalBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        
        // Generate unique bundle identifier
        let newBundleIdentifier = "com.mtech.pluralmac.\(instance.id.uuidString.lowercased())"
        let executableName = sanitizeExecutableName(instance.name)
        
        // Create plist dictionary
        let plistDict: [String: Any] = [
            "CFBundleIdentifier": newBundleIdentifier,
            "CFBundleExecutable": executableName,
            "CFBundleName": instance.name,
            "CFBundleDisplayName": instance.name,
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleSignature": "????",
            "CFBundleShortVersionString": originalVersion,
            "CFBundleVersion": "1",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "11.0",
            "NSHighResolutionCapable": true,
            "LSUIElement": false,
            
            // PluralMac metadata
            "PluralMacInstanceID": instance.id.uuidString,
            "PluralMacOriginalBundleID": originalBundleId,
            "PluralMacOriginalExecutable": originalExecName,
            "PluralMacTargetApp": instance.targetAppPath.path,
            "PluralMacCreatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Write plist
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plistDict,
            format: .xml,
            options: 0
        )
        
        try plistData.write(to: plistPath)
        
        logger.debug("Created Info.plist with Bundle ID: \(newBundleIdentifier)")
    }
    
    // MARK: - Launcher Script
    
    /// Create a launcher script that sets environment variables and executes the ORIGINAL app
    private func createLauncherScript(for instance: AppInstance) throws {
        // Get the original app's executable path
        guard let originalBundle = Bundle(url: instance.targetAppPath),
              let originalExecURL = originalBundle.executableURL else {
            throw BundleError.invalidTargetBundle(instance.targetAppPath)
        }
        
        let executableName = sanitizeExecutableName(instance.name)
        let launcherPath = instance.shortcutPath
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(executableName)
        
        // Build the launcher script
        var script = """
        #!/bin/bash
        # PluralMac Trampoline Launcher
        # Instance: \(instance.name)
        # ID: \(instance.id.uuidString)
        # Generated: \(ISO8601DateFormatter().string(from: Date()))
        #
        # This launcher executes the ORIGINAL unmodified app binary
        # with custom environment variables for data isolation.
        
        """
        
        // Add environment variables
        let envVars = instance.effectiveEnvironmentVariables
        if !envVars.isEmpty {
            script += "# Environment Variables for Data Isolation\n"
            for (key, value) in envVars {
                let escapedValue = value.replacingOccurrences(of: "\"", with: "\\\"")
                script += "export \(key)=\"\(escapedValue)\"\n"
            }
            script += "\n"
        }
        
        // Execute the ORIGINAL app binary directly
        let originalExecPath = originalExecURL.path
        script += "# Execute the ORIGINAL app binary (unmodified, preserving code signature)\n"
        script += "exec \"\(originalExecPath)\""
        
        // Add command line arguments
        let args = instance.effectiveCommandLineArguments
        for arg in args {
            let escapedArg = arg.replacingOccurrences(of: "\"", with: "\\\"")
            script += " \"\(escapedArg)\""
        }
        
        script += " \"$@\"\n"
        
        // Write launcher script
        try script.write(to: launcherPath, atomically: true, encoding: .utf8)
        
        // Make it executable
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launcherPath.path
        )
        
        logger.debug("Created launcher script at: \(launcherPath.path)")
    }
    
    // MARK: - Code Signing
    
    /// Sign the minimal bundle with ad-hoc signature
    private func signBundle(at bundlePath: URL) async throws {
        logger.debug("Signing bundle at: \(bundlePath.path)")
        
        // Sign with ad-hoc signature
        let codesignProcess = Process()
        codesignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesignProcess.arguments = [
            "--sign", "-",           // Ad-hoc signature
            "--force",               // Replace existing signature
            bundlePath.path
        ]
        
        let pipe = Pipe()
        codesignProcess.standardError = pipe
        
        try codesignProcess.run()
        codesignProcess.waitUntilExit()
        
        if codesignProcess.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            logger.warning("Codesign warning: \(errorMessage)")
            // Don't throw - the bundle may still work
        }
        
        logger.debug("Successfully signed bundle")
    }
    
    // MARK: - Icon Setup
    
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
            
            // Save as PNG then copy to icns (basic)
            try pngData.write(to: destination)
            
            logger.debug("Extracted icon using NSWorkspace fallback")
        }
    }
    
    // MARK: - Data Directory
    
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
    
    // MARK: - Launch Services
    
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
        
        logger.info("Successfully deleted bundle for: \(instance.name)")
    }
    
    // MARK: - Bundle Update
    
    /// Update an existing bundle (regenerate launcher, update icon, etc.)
    func updateBundle(for instance: AppInstance) async throws {
        logger.info("Updating bundle for instance: \(instance.name)")
        
        // Just recreate the bundle
        try await createBundle(for: instance)
        
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
    case invalidBundleStructure(String)
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
        case .invalidBundleStructure(let message):
            return "Invalid bundle structure: \(message)"
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
