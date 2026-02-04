//
//  AppTypeDetector.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import OSLog

/// Service responsible for detecting the type of macOS applications
/// and providing appropriate configuration recommendations.
final class AppTypeDetector: Sendable {
    
    // MARK: - Singleton
    
    static let shared = AppTypeDetector()
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "AppTypeDetector")
    
    // MARK: - Known App Identifiers
    
    /// Known Chromium-based browser identifiers
    private let chromiumIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.vivaldi.Vivaldi",
        "com.vivaldi.Vivaldi.snapshot",
        "company.thebrowser.Browser", // Arc
        "org.chromium.Chromium",
        "com.operasoftware.Opera",
        "com.nicothin.nickel",
        "com.nicothin.nickel.dev",
        "com.nicothin.nickel.beta",
        "ru.nicothin.nickel",
        "io.nickel.nickel",
        "com.nickel.Nickel",
        "io.nickel.Nickel"
    ]
    
    /// Known Firefox-based browser identifiers
    private let firefoxIdentifiers: Set<String> = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "org.waterfox.waterfox",
        "org.waterfoxproject.waterfox",
        "io.gitlab.librewolf-community",
        "org.torproject.torbrowser",
        "net.mullvad.mullvadbrowser"
    ]
    
    /// Known ToDesktop-based app identifiers
    private let toDesktopIdentifiers: Set<String> = [
        "com.todesktop.cursor",
        "todesktop.com.cursor",
        "com.linear.Linear",
        "com.todesktop.linear"
    ]
    
    /// Known Electron apps (common ones)
    private let electronIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.hnc.DiscordPTB",
        "com.hnc.DiscordCanary",
        "notion.id",
        "com.spotify.client",
        "com.figma.Desktop",
        "md.obsidian",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.todoist.mac.Todoist",
        "com.postmanlabs.mac",
        "io.zsa.wally",
        "com.github.GitHubClient"
    ]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Detect the type of application at the given URL
    /// - Parameter url: Path to the .app bundle
    /// - Returns: The detected AppType
    func detect(at url: URL) -> AppType {
        logger.debug("Detecting app type for: \(url.path)")
        
        guard let bundle = Bundle(url: url) else {
            logger.warning("Invalid bundle at: \(url.path)")
            return .generic
        }
        
        guard let bundleId = bundle.bundleIdentifier else {
            logger.warning("No bundle identifier for: \(url.path)")
            return .generic
        }
        
        // Check for system apps first
        if bundleId.hasPrefix("com.apple.") {
            logger.info("System app detected: \(bundleId)")
            return .system
        }
        
        // Check for sandboxed apps
        if isSandboxed(bundle: bundle) {
            logger.info("Sandboxed app detected: \(bundleId)")
            return .sandboxed
        }
        
        // Check known identifiers
        if let type = detectByIdentifier(bundleId) {
            logger.info("Known app detected: \(bundleId) -> \(type.rawValue)")
            return type
        }
        
        // Check bundle contents
        if let type = detectByBundleContents(bundle: bundle) {
            logger.info("App type detected by contents: \(bundleId) -> \(type.rawValue)")
            return type
        }
        
        logger.info("Generic app: \(bundleId)")
        return .generic
    }
    
    /// Check if an app is sandboxed
    /// - Parameter bundle: The app bundle
    /// - Returns: true if the app is sandboxed
    func isSandboxed(bundle: Bundle) -> Bool {
        // Check for App Store receipt (most reliable indicator)
        if let receiptURL = bundle.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: receiptURL.path) {
            return true
        }
        
        // Check for sandbox container metadata
        // Apps from App Store have specific entitlements
        let entitlementsPath = bundle.bundlePath + "/Contents/embedded.provisionprofile"
        if FileManager.default.fileExists(atPath: entitlementsPath) {
            return true
        }
        
        return false
    }
    
    /// Get recommended arguments for data isolation
    /// - Parameters:
    ///   - appType: The type of application
    ///   - dataPath: Path to the isolated data directory
    /// - Returns: Array of command-line arguments
    func recommendedArguments(for appType: AppType, dataPath: URL) -> [String] {
        switch appType {
        case .chromium:
            return [
                "--user-data-dir=\(dataPath.path)",
                "--no-first-run"
            ]
        case .firefox:
            return [
                "-profile",
                dataPath.path,
                "-no-remote"
            ]
        case .electron, .toDesktop, .generic:
            // These typically use HOME redirection, no special args
            return []
        case .sandboxed, .system:
            return []
        }
    }
    
    /// Get recommended environment variables for data isolation
    /// - Parameters:
    ///   - appType: The type of application
    ///   - dataPath: Path to the isolated data directory
    /// - Returns: Dictionary of environment variables
    func recommendedEnvironment(for appType: AppType, dataPath: URL) -> [String: String] {
        switch appType {
        case .electron, .toDesktop, .generic:
            return ["HOME": dataPath.path]
        case .chromium:
            // Chromium uses --user-data-dir, but HOME can be helpful too
            return ["HOME": dataPath.path]
        case .firefox:
            // Firefox uses -profile
            return [:]
        case .sandboxed, .system:
            return [:]
        }
    }
    
    // MARK: - Private Detection Methods
    
    /// Detect app type by known bundle identifier
    private func detectByIdentifier(_ bundleId: String) -> AppType? {
        // Check exact matches first
        if chromiumIdentifiers.contains(bundleId) {
            return .chromium
        }
        
        if firefoxIdentifiers.contains(bundleId) {
            return .firefox
        }
        
        if toDesktopIdentifiers.contains(bundleId) {
            return .toDesktop
        }
        
        if electronIdentifiers.contains(bundleId) {
            return .electron
        }
        
        // Check prefix matches for variants
        for id in chromiumIdentifiers {
            if bundleId.hasPrefix(id) {
                return .chromium
            }
        }
        
        for id in firefoxIdentifiers {
            if bundleId.hasPrefix(id) {
                return .firefox
            }
        }
        
        return nil
    }
    
    /// Detect app type by examining bundle contents
    private func detectByBundleContents(bundle: Bundle) -> AppType? {
        let frameworksPath = bundle.bundlePath + "/Contents/Frameworks"
        
        // Check for ToDesktop first (it's more specific than Electron)
        if isToDesktopApp(frameworksPath: frameworksPath, bundle: bundle) {
            return .toDesktop
        }
        
        // Check for Electron
        if isElectronApp(frameworksPath: frameworksPath) {
            return .electron
        }
        
        // Check for Chromium framework (for forks we might not know)
        if isChromiumApp(frameworksPath: frameworksPath) {
            return .chromium
        }
        
        return nil
    }
    
    /// Check if app is built with ToDesktop
    private func isToDesktopApp(frameworksPath: String, bundle: Bundle) -> Bool {
        let fm = FileManager.default
        
        // Check for ToDesktop helper apps
        let toDesktopMarkers = [
            "ToDesktop Runtime Helper.app",
            "ToDesktopRuntimeHelper.app",
            "ToDesktop Helper.app"
        ]
        
        for marker in toDesktopMarkers {
            if fm.fileExists(atPath: frameworksPath + "/" + marker) {
                return true
            }
        }
        
        // Check Info.plist for ToDesktop keys
        if let info = bundle.infoDictionary {
            let toDesktopKeys = ["ToDesktopAppId", "ToDesktopProductId", "ToDesktopUpdateURL"]
            for key in toDesktopKeys {
                if info[key] != nil {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Check if app is built with Electron
    private func isElectronApp(frameworksPath: String) -> Bool {
        let electronFramework = frameworksPath + "/Electron Framework.framework"
        return FileManager.default.fileExists(atPath: electronFramework)
    }
    
    /// Check if app is Chromium-based (has Chromium framework)
    private func isChromiumApp(frameworksPath: String) -> Bool {
        let fm = FileManager.default
        
        // Check for Chromium Framework
        let chromiumMarkers = [
            "Chromium Framework.framework",
            "Google Chrome Framework.framework"
        ]
        
        for marker in chromiumMarkers {
            if fm.fileExists(atPath: frameworksPath + "/" + marker) {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Batch Operations

extension AppTypeDetector {
    
    /// Scan the Applications folder and return all compatible apps
    /// - Returns: Array of URLs to compatible applications
    func scanApplicationsFolder() async -> [URL] {
        let applicationsPath = "/Applications"
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: applicationsPath),
            includingPropertiesForKeys: [.isApplicationKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        return contents.filter { url in
            url.pathExtension == "app" && detect(at: url).supportsDataIsolation
        }
    }
    
    /// Classify multiple apps at once
    /// - Parameter urls: Array of app bundle URLs
    /// - Returns: Dictionary mapping URLs to their AppType
    func classifyApps(_ urls: [URL]) -> [URL: AppType] {
        var results: [URL: AppType] = [:]
        for url in urls {
            results[url] = detect(at: url)
        }
        return results
    }
}
