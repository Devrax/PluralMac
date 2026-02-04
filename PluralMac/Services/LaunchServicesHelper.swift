//
//  LaunchServicesHelper.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import CoreServices
import OSLog

/// Helper service for interacting with macOS Launch Services.
/// Handles app registration, Dock integration, and file type associations.
struct LaunchServicesHelper: Sendable {
    
    // MARK: - Properties
    
    private static let logger = Logger(subsystem: "com.mtech.PluralMac", category: "LaunchServices")
    
    // MARK: - Registration
    
    /// Register an application bundle with Launch Services
    /// - Parameter bundleURL: Path to the .app bundle
    /// - Returns: true if registration was successful
    @discardableResult
    static func register(_ bundleURL: URL) -> Bool {
        let status = LSRegisterURL(bundleURL as CFURL, true)
        
        if status == noErr {
            logger.info("Successfully registered: \(bundleURL.lastPathComponent)")
            return true
        } else {
            logger.warning("Failed to register \(bundleURL.lastPathComponent): error \(status)")
            return false
        }
    }
    
    /// Register multiple bundles at once
    /// - Parameter bundleURLs: Array of bundle URLs to register
    /// - Returns: Number of successfully registered bundles
    static func registerAll(_ bundleURLs: [URL]) -> Int {
        var successCount = 0
        for url in bundleURLs {
            if register(url) {
                successCount += 1
            }
        }
        return successCount
    }
    
    // MARK: - Application Info
    
    /// Get the display name for an application
    /// - Parameter bundleURL: Path to the .app bundle
    /// - Returns: The display name or nil if not found
    static func displayName(for bundleURL: URL) -> String? {
        guard let bundle = Bundle(url: bundleURL) else { return nil }
        
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
    }
    
    /// Get the bundle identifier for an application
    /// - Parameter bundleURL: Path to the .app bundle
    /// - Returns: The bundle identifier or nil if not found
    static func bundleIdentifier(for bundleURL: URL) -> String? {
        Bundle(url: bundleURL)?.bundleIdentifier
    }
    
    /// Get the version string for an application
    /// - Parameter bundleURL: Path to the .app bundle
    /// - Returns: The version string or nil if not found
    static func version(for bundleURL: URL) -> String? {
        guard let bundle = Bundle(url: bundleURL) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
    
    // MARK: - Launch
    
    /// Launch an application bundle
    /// - Parameters:
    ///   - bundleURL: Path to the .app bundle to launch
    ///   - arguments: Optional command-line arguments
    ///   - environment: Optional environment variables
    /// - Returns: The launched NSRunningApplication or throws an error
    @MainActor
    static func launch(
        _ bundleURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.environment = environment
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        
        var launchedApp: NSRunningApplication?
        var launchError: Error?
        
        let semaphore = DispatchSemaphore(value: 0)
        
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration
        ) { app, error in
            launchedApp = app
            launchError = error
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = launchError {
            throw LaunchError.launchFailed(bundleURL, error)
        }
        
        guard let app = launchedApp else {
            throw LaunchError.noAppReturned(bundleURL)
        }
        
        logger.info("Launched: \(bundleURL.lastPathComponent)")
        return app
    }
    
    /// Launch an application asynchronously
    @MainActor
    static func launchAsync(
        _ bundleURL: URL,
        arguments: [String] = [],
        environment: [String: String] = []
    ) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.environment = environment
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        
        do {
            let app = try await NSWorkspace.shared.openApplication(
                at: bundleURL,
                configuration: configuration
            )
            logger.info("Launched: \(bundleURL.lastPathComponent)")
            return app
        } catch {
            throw LaunchError.launchFailed(bundleURL, error)
        }
    }
    
    // MARK: - Finder Integration
    
    /// Reveal an item in Finder
    /// - Parameter url: The file or folder URL to reveal
    @MainActor
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
    
    /// Open the parent folder of an item in Finder
    /// - Parameter url: The file or folder URL
    @MainActor
    static func openContainingFolder(_ url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    // MARK: - Dock Integration
    
    /// Check if an app is currently running
    /// - Parameter bundleIdentifier: The bundle identifier to check
    /// - Returns: true if the app is running
    @MainActor
    static func isRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
    }
    
    /// Get all running instances of an app
    /// - Parameter bundleIdentifier: The bundle identifier
    /// - Returns: Array of running applications
    @MainActor
    static func runningInstances(bundleIdentifier: String) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier
        }
    }
    
    /// Terminate a running application
    /// - Parameter bundleIdentifier: The bundle identifier
    /// - Returns: true if termination was initiated
    @MainActor
    @discardableResult
    static func terminate(bundleIdentifier: String) -> Bool {
        let apps = runningInstances(bundleIdentifier: bundleIdentifier)
        var terminated = false
        
        for app in apps {
            if app.terminate() {
                terminated = true
            }
        }
        
        return terminated
    }
    
    /// Force terminate a running application
    /// - Parameter bundleIdentifier: The bundle identifier
    /// - Returns: true if force termination was initiated
    @MainActor
    @discardableResult
    static func forceTerminate(bundleIdentifier: String) -> Bool {
        let apps = runningInstances(bundleIdentifier: bundleIdentifier)
        var terminated = false
        
        for app in apps {
            if app.forceTerminate() {
                terminated = true
            }
        }
        
        return terminated
    }
}

// MARK: - Errors

enum LaunchError: LocalizedError {
    case launchFailed(URL, Error)
    case noAppReturned(URL)
    case appNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .launchFailed(let url, let error):
            return "Failed to launch \(url.lastPathComponent): \(error.localizedDescription)"
        case .noAppReturned(let url):
            return "No application returned after launching: \(url.lastPathComponent)"
        case .appNotFound(let identifier):
            return "Application not found: \(identifier)"
        }
    }
}

// MARK: - AppKit Import

import AppKit
