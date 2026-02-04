//
//  Application.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import AppKit

/// Represents a macOS application that can be used as a target for creating instances.
struct Application: Identifiable, Codable, Hashable, Sendable {
    
    // MARK: - Properties
    
    /// Unique identifier (usually the bundle identifier)
    let id: String
    
    /// Bundle identifier (e.g., "com.google.Chrome")
    let bundleIdentifier: String
    
    /// Display name of the application
    let name: String
    
    /// Path to the .app bundle
    let path: URL
    
    /// Path to the executable binary inside the bundle
    let executablePath: URL
    
    /// Detected app type for data isolation strategy
    let appType: AppType
    
    /// Version string from Info.plist
    let version: String?
    
    /// Whether the app is sandboxed (Mac App Store apps)
    let isSandboxed: Bool
    
    /// Bundle icon file name (for extraction)
    let iconFileName: String?
    
    // MARK: - Initialization
    
    /// Initialize from a bundle URL
    /// - Parameter url: Path to the .app bundle
    /// - Throws: ApplicationError if the bundle is invalid or unsupported
    init(from url: URL) throws {
        guard let bundle = Bundle(url: url) else {
            throw ApplicationError.invalidBundle(url)
        }
        
        guard let bundleId = bundle.bundleIdentifier else {
            throw ApplicationError.missingBundleIdentifier(url)
        }
        
        guard let executableURL = bundle.executableURL else {
            throw ApplicationError.missingExecutable(url)
        }
        
        // Check for Apple system apps
        if bundleId.hasPrefix("com.apple.") {
            throw ApplicationError.systemAppNotSupported(bundleId)
        }
        
        self.id = bundleId
        self.bundleIdentifier = bundleId
        self.path = url
        self.executablePath = executableURL
        
        // Get display name (prefer localized name, fallback to bundle name)
        self.name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        
        // Get version
        self.version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        
        // Get icon file name
        self.iconFileName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String
        
        // Detect if sandboxed
        self.isSandboxed = Self.checkIfSandboxed(bundle: bundle)
        
        // Detect app type
        self.appType = Self.detectAppType(
            bundleIdentifier: bundleId,
            bundle: bundle,
            isSandboxed: self.isSandboxed
        )
    }
    
    // MARK: - Static Detection Methods
    
    /// Check if an app is sandboxed by looking for entitlements
    private static func checkIfSandboxed(bundle: Bundle) -> Bool {
        // Check for App Sandbox entitlement in the code signature
        // Sandboxed apps have specific container paths
        let bundlePath = bundle.bundlePath
        
        // Quick heuristic: Mac App Store apps are typically in /Applications
        // and have receipt files
        let receiptPath = bundle.appStoreReceiptURL
        if let receipt = receiptPath, FileManager.default.fileExists(atPath: receipt.path) {
            return true
        }
        
        // Check for sandbox container
        // Apps with "com.apple.security.app-sandbox" entitlement are sandboxed
        // This is a simplified check - full check would require codesign parsing
        return false
    }
    
    /// Detect the type of application based on bundle contents and identifier
    private static func detectAppType(
        bundleIdentifier: String,
        bundle: Bundle,
        isSandboxed: Bool
    ) -> AppType {
        // Sandboxed apps cannot be isolated
        if isSandboxed {
            return .sandboxed
        }
        
        // Check for known Chromium-based browsers
        let chromiumIdentifiers = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.Dev",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "company.thebrowser.Browser", // Arc
            "org.chromium.Chromium",
            "com.operasoftware.Opera",
            "com.nicothin.nickel" // Nickel Browser
        ]
        if chromiumIdentifiers.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return .chromium
        }
        
        // Check for Firefox-based browsers
        let firefoxIdentifiers = [
            "org.mozilla.firefox",
            "org.mozilla.nightly",
            "org.waterfox.waterfox",
            "io.gitlab.librewolf-community"
        ]
        if firefoxIdentifiers.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return .firefox
        }
        
        // Check for ToDesktop apps (check framework in bundle)
        if Self.isToDesktopApp(bundle: bundle) {
            return .toDesktop
        }
        
        // Check for Electron apps
        if Self.isElectronApp(bundle: bundle) {
            return .electron
        }
        
        // Default to generic
        return .generic
    }
    
    /// Check if app is built with ToDesktop
    private static func isToDesktopApp(bundle: Bundle) -> Bool {
        // ToDesktop apps have specific markers in their bundle
        let frameworksPath = bundle.bundlePath + "/Contents/Frameworks"
        let toDesktopMarkers = [
            "ToDesktop Runtime Helper.app",
            "ToDesktopRuntimeHelper"
        ]
        
        for marker in toDesktopMarkers {
            if FileManager.default.fileExists(atPath: frameworksPath + "/" + marker) {
                return true
            }
        }
        
        // Also check Info.plist for ToDesktop markers
        if let infoPlist = bundle.infoDictionary {
            if infoPlist["ToDesktopAppId"] != nil || infoPlist["ToDesktopProductId"] != nil {
                return true
            }
        }
        
        return false
    }
    
    /// Check if app is built with Electron
    private static func isElectronApp(bundle: Bundle) -> Bool {
        let frameworksPath = bundle.bundlePath + "/Contents/Frameworks"
        let electronFramework = frameworksPath + "/Electron Framework.framework"
        
        return FileManager.default.fileExists(atPath: electronFramework)
    }
    
    // MARK: - Validation
    
    /// Validates if this application can be used to create instances
    func validate() throws {
        // Check if path still exists
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ApplicationError.appNotFound(path)
        }
        
        // Check if executable is accessible
        guard FileManager.default.isExecutableFile(atPath: executablePath.path) else {
            throw ApplicationError.executableNotAccessible(executablePath)
        }
        
        // Check if app type is supported
        guard appType.supportsDataIsolation else {
            throw ApplicationError.unsupportedAppType(appType)
        }
    }
}

// MARK: - Errors

/// Errors that can occur when working with Applications
enum ApplicationError: LocalizedError {
    case invalidBundle(URL)
    case missingBundleIdentifier(URL)
    case missingExecutable(URL)
    case systemAppNotSupported(String)
    case appNotFound(URL)
    case executableNotAccessible(URL)
    case unsupportedAppType(AppType)
    
    var errorDescription: String? {
        switch self {
        case .invalidBundle(let url):
            return "Invalid application bundle at: \(url.path)"
        case .missingBundleIdentifier(let url):
            return "Application has no bundle identifier: \(url.path)"
        case .missingExecutable(let url):
            return "Application has no executable: \(url.path)"
        case .systemAppNotSupported(let bundleId):
            return "Apple system apps are not supported: \(bundleId)"
        case .appNotFound(let url):
            return "Application not found at: \(url.path)"
        case .executableNotAccessible(let url):
            return "Cannot access executable: \(url.path)"
        case .unsupportedAppType(let type):
            return "App type '\(type.displayName)' does not support data isolation"
        }
    }
}

// MARK: - Convenience Extensions

extension Application {
    /// Get the icon image for this application
    @MainActor
    var icon: NSImage? {
        NSWorkspace.shared.icon(forFile: path.path)
    }
    
    /// Check if this app is a browser
    var isBrowser: Bool {
        appType == .chromium || appType == .firefox
    }
    
    /// Get recommended command-line arguments for data isolation
    func dataIsolationArguments(dataPath: URL) -> [String] {
        switch appType {
        case .chromium:
            return ["--user-data-dir=\(dataPath.path)"]
        case .firefox:
            return ["-profile", dataPath.path]
        default:
            return []
        }
    }
}
