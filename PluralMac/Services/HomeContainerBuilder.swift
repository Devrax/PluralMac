//
//  HomeContainerBuilder.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import OSLog

/// Service responsible for building isolated HOME directory containers
/// with appropriate symlinks to preserve essential macOS functionality.
struct HomeContainerBuilder: Sendable {
    
    // MARK: - Properties
    
    private static let logger = Logger(subsystem: "com.mtech.PluralMac", category: "HomeContainerBuilder")
    private static let fileManager = FileManager.default
    
    // MARK: - Container Configuration
    
    /// Directories that should be symlinked to the real HOME (shared across instances)
    static let sharedDirectories: [String] = [
        // User folders
        "Desktop",
        "Documents",
        "Downloads",
        "Movies",
        "Music",
        "Pictures",
        "Public",
        
        // Essential Library items that must be shared
        "Library/Keychains",                    // System keychain access
        "Library/Group Containers",             // App groups
        "Library/Fonts",                        // User fonts
    ]
    
    /// Individual files that should be symlinked (security preferences, etc.)
    static let sharedFiles: [String] = [
        "Library/Preferences/com.apple.security.plist",
        "Library/Preferences/.GlobalPreferences.plist",
    ]
    
    /// Directories that should be created (isolated per instance)
    static let isolatedDirectories: [String] = [
        "Library",
        "Library/Application Support",
        "Library/Caches",
        "Library/Containers",
        "Library/Cookies",
        "Library/HTTPStorages",
        "Library/Logs",
        "Library/Preferences",
        "Library/Saved Application State",
        "Library/WebKit",
    ]
    
    // MARK: - Build Methods
    
    /// Build a complete HOME container for an app instance
    /// - Parameters:
    ///   - containerPath: Path where the container should be created
    ///   - appType: Type of app (affects container structure)
    /// - Throws: ContainerError if creation fails
    static func buildContainer(
        at containerPath: URL,
        for appType: AppType
    ) throws {
        logger.info("Building HOME container at: \(containerPath.path)")
        
        let realHome = fileManager.homeDirectoryForCurrentUser
        
        // Create the container directory
        if !fileManager.fileExists(atPath: containerPath.path) {
            try fileManager.createDirectory(
                at: containerPath,
                withIntermediateDirectories: true
            )
        }
        
        // Create isolated directories
        for relativePath in isolatedDirectories {
            let fullPath = containerPath.appendingPathComponent(relativePath)
            if !fileManager.fileExists(atPath: fullPath.path) {
                try fileManager.createDirectory(
                    at: fullPath,
                    withIntermediateDirectories: true
                )
            }
        }
        
        // Create symlinks to shared directories
        for relativePath in sharedDirectories {
            try createSymlinkIfNeeded(
                from: containerPath.appendingPathComponent(relativePath),
                to: realHome.appendingPathComponent(relativePath)
            )
        }
        
        // Create symlinks to shared files
        for relativePath in sharedFiles {
            try createSymlinkIfNeeded(
                from: containerPath.appendingPathComponent(relativePath),
                to: realHome.appendingPathComponent(relativePath)
            )
        }
        
        // Apply app-type specific setup
        try applyAppTypeSpecificSetup(at: containerPath, for: appType)
        
        logger.info("Successfully built HOME container")
    }
    
    /// Create a symlink if it doesn't exist and the target exists
    private static func createSymlinkIfNeeded(from linkPath: URL, to targetPath: URL) throws {
        // Skip if link already exists
        if fileManager.fileExists(atPath: linkPath.path) {
            return
        }
        
        // Skip if target doesn't exist
        guard fileManager.fileExists(atPath: targetPath.path) else {
            logger.debug("Skipping symlink (target doesn't exist): \(targetPath.path)")
            return
        }
        
        // Create parent directory if needed
        let parentDir = linkPath.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true
            )
        }
        
        // Create the symlink
        try fileManager.createSymbolicLink(
            at: linkPath,
            withDestinationURL: targetPath
        )
        
        logger.debug("Created symlink: \(linkPath.lastPathComponent)")
    }
    
    /// Apply app-type specific container setup
    private static func applyAppTypeSpecificSetup(at containerPath: URL, for appType: AppType) throws {
        switch appType {
        case .chromium:
            // Chromium apps use --user-data-dir, but may still need some Library structure
            try createDirectoryIfNeeded(
                containerPath.appendingPathComponent("Library/Application Support/Google")
            )
            
        case .firefox:
            // Firefox uses -profile, create Mozilla directory structure
            try createDirectoryIfNeeded(
                containerPath.appendingPathComponent("Library/Application Support/Mozilla")
            )
            try createDirectoryIfNeeded(
                containerPath.appendingPathComponent("Library/Caches/Mozilla")
            )
            
        case .electron, .toDesktop:
            // Electron apps typically need Application Support and Caches
            // Already covered by isolatedDirectories
            break
            
        case .generic:
            // Generic apps get the standard setup
            break
            
        case .sandboxed, .system:
            // These shouldn't get containers
            logger.warning("Attempted to create container for unsupported app type: \(appType.rawValue)")
        }
    }
    
    /// Create a directory if it doesn't exist
    private static func createDirectoryIfNeeded(_ path: URL) throws {
        if !fileManager.fileExists(atPath: path.path) {
            try fileManager.createDirectory(
                at: path,
                withIntermediateDirectories: true
            )
        }
    }
    
    // MARK: - Cleanup Methods
    
    /// Remove a HOME container and all its contents
    /// - Parameter containerPath: Path to the container
    /// - Parameter preserveSharedLinks: If true, only removes isolated data (not symlinks targets)
    static func removeContainer(at containerPath: URL, preserveSharedLinks: Bool = true) throws {
        logger.info("Removing HOME container at: \(containerPath.path)")
        
        guard fileManager.fileExists(atPath: containerPath.path) else {
            logger.debug("Container doesn't exist, nothing to remove")
            return
        }
        
        if preserveSharedLinks {
            // Only remove the container directory, symlinks will just be removed
            // without affecting their targets
            try fileManager.removeItem(at: containerPath)
        } else {
            // Remove everything (dangerous - could delete user data if symlinks broken)
            try fileManager.removeItem(at: containerPath)
        }
        
        logger.info("Successfully removed HOME container")
    }
    
    /// Get the total size of isolated data (excluding symlinked directories)
    static func isolatedDataSize(at containerPath: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: containerPath.path) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: containerPath,
            includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isDirectoryKey]
            )
            
            // Skip symbolic links (they point to shared data)
            if resourceValues.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            
            // Count file sizes
            if resourceValues.isDirectory == false {
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
        }
        
        return totalSize
    }
    
    // MARK: - Validation
    
    /// Validate that a container is properly set up
    static func validateContainer(at containerPath: URL) -> ContainerValidationResult {
        var missingDirectories: [String] = []
        var brokenSymlinks: [String] = []
        
        // Check isolated directories exist
        for relativePath in isolatedDirectories {
            let fullPath = containerPath.appendingPathComponent(relativePath)
            if !fileManager.fileExists(atPath: fullPath.path) {
                missingDirectories.append(relativePath)
            }
        }
        
        // Check symlinks are valid
        for relativePath in sharedDirectories {
            let linkPath = containerPath.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: linkPath.path) {
                // Check if it's a valid symlink
                do {
                    let destination = try fileManager.destinationOfSymbolicLink(atPath: linkPath.path)
                    if !fileManager.fileExists(atPath: destination) {
                        brokenSymlinks.append(relativePath)
                    }
                } catch {
                    // Not a symlink or can't read it
                    continue
                }
            }
        }
        
        return ContainerValidationResult(
            isValid: missingDirectories.isEmpty && brokenSymlinks.isEmpty,
            missingDirectories: missingDirectories,
            brokenSymlinks: brokenSymlinks
        )
    }
}

// MARK: - Supporting Types

/// Result of container validation
struct ContainerValidationResult: Sendable {
    let isValid: Bool
    let missingDirectories: [String]
    let brokenSymlinks: [String]
    
    var issues: [String] {
        var result: [String] = []
        
        for dir in missingDirectories {
            result.append("Missing directory: \(dir)")
        }
        
        for link in brokenSymlinks {
            result.append("Broken symlink: \(link)")
        }
        
        return result
    }
}

// MARK: - Errors

enum ContainerError: LocalizedError {
    case creationFailed(URL, Error)
    case symlinkFailed(URL, URL)
    case invalidPath(URL)
    case permissionDenied(URL)
    
    var errorDescription: String? {
        switch self {
        case .creationFailed(let url, let error):
            return "Failed to create container at \(url.path): \(error.localizedDescription)"
        case .symlinkFailed(let link, let target):
            return "Failed to create symlink from \(link.path) to \(target.path)"
        case .invalidPath(let url):
            return "Invalid container path: \(url.path)"
        case .permissionDenied(let url):
            return "Permission denied: \(url.path)"
        }
    }
}
