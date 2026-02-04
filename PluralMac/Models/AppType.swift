//
//  AppType.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation

/// Represents the type of macOS application for determining
/// the appropriate data isolation strategy.
enum AppType: String, Codable, CaseIterable, Sendable {
    /// Chromium-based browsers (Chrome, Edge, Brave, Vivaldi, Arc, etc.)
    /// Uses `--user-data-dir` for data isolation
    case chromium
    
    /// Firefox-based browsers (Firefox, Waterfox, LibreWolf, etc.)
    /// Uses `-profile` argument for data isolation
    case firefox
    
    /// Electron-based apps (VS Code, Slack, Discord, Notion, etc.)
    /// Uses HOME redirection or app-specific flags
    case electron
    
    /// ToDesktop-based apps (Cursor IDE, Linear, etc.)
    /// Similar to Electron, uses HOME redirection
    case toDesktop
    
    /// Generic non-sandboxed apps
    /// Uses HOME environment variable redirection
    case generic
    
    /// Mac App Store sandboxed apps - NOT SUPPORTED for data isolation
    case sandboxed
    
    /// Apple system apps (com.apple.*) - NOT SUPPORTED
    case system
    
    // MARK: - Computed Properties
    
    /// Whether this app type supports data isolation
    var supportsDataIsolation: Bool {
        switch self {
        case .chromium, .firefox, .electron, .toDesktop, .generic:
            return true
        case .sandboxed, .system:
            return false
        }
    }
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .chromium: return "Chromium-based Browser"
        case .firefox: return "Firefox-based Browser"
        case .electron: return "Electron App"
        case .toDesktop: return "ToDesktop App"
        case .generic: return "Generic App"
        case .sandboxed: return "Sandboxed App (Not Supported)"
        case .system: return "System App (Not Supported)"
        }
    }
    
    /// Recommended data isolation method
    var isolationMethod: DataIsolationMethod {
        switch self {
        case .chromium:
            return .userDataDir
        case .firefox:
            return .profileArgument
        case .electron, .toDesktop, .generic:
            return .homeRedirection
        case .sandboxed, .system:
            return .none
        }
    }
    
    /// Compatibility indicator for UI
    var compatibilityLevel: CompatibilityLevel {
        switch self {
        case .chromium, .firefox:
            return .full
        case .electron, .toDesktop:
            return .full
        case .generic:
            return .partial
        case .sandboxed, .system:
            return .unsupported
        }
    }
}

// MARK: - Supporting Types

/// Method used to isolate data between instances
enum DataIsolationMethod: String, Codable, Sendable {
    /// Use `--user-data-dir` argument (Chromium)
    case userDataDir
    
    /// Use `-profile` argument (Firefox)
    case profileArgument
    
    /// Override HOME environment variable
    case homeRedirection
    
    /// No isolation possible
    case none
}

/// UI indicator for app compatibility
enum CompatibilityLevel: String, Codable, Sendable {
    /// ✅ Fully supported and tested
    case full
    
    /// ⚠️ May work, not fully tested
    case partial
    
    /// ❌ Not supported
    case unsupported
    
    /// SF Symbol name for the indicator
    var symbolName: String {
        switch self {
        case .full: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .unsupported: return "xmark.circle.fill"
        }
    }
    
    /// Color name for the indicator
    var colorName: String {
        switch self {
        case .full: return "green"
        case .partial: return "yellow"
        case .unsupported: return "red"
        }
    }
}
