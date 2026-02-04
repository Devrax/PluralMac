//
//  IconExtractor.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import AppKit
import OSLog

/// Service for extracting icons from macOS applications and converting between formats.
actor IconExtractor {
    
    // MARK: - Singleton
    
    static let shared = IconExtractor()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "IconExtractor")
    private let fileManager = FileManager.default
    private let cache = IconCache.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Icon Extraction
    
    /// Extract icon from an application bundle
    /// - Parameters:
    ///   - appURL: Path to the .app bundle
    ///   - size: Desired icon size (default 512 for high quality)
    /// - Returns: NSImage of the extracted icon
    func extractIcon(from appURL: URL, size: Int = 512) async throws -> NSImage {
        logger.debug("Extracting icon from: \(appURL.lastPathComponent)")
        
        // Check cache first
        if let cached = await cache.get(for: appURL) {
            logger.debug("Using cached icon for: \(appURL.lastPathComponent)")
            return cached
        }
        
        // Try to extract from bundle directly
        if let bundleIcon = try? extractFromBundle(appURL: appURL) {
            await cache.set(bundleIcon, for: appURL)
            return bundleIcon
        }
        
        // Fallback to NSWorkspace
        let icon = await extractUsingWorkspace(appURL: appURL, size: size)
        await cache.set(icon, for: appURL)
        
        return icon
    }
    
    /// Extract icon directly from the app bundle's Resources
    private func extractFromBundle(appURL: URL) throws -> NSImage? {
        guard let bundle = Bundle(url: appURL) else {
            return nil
        }
        
        // Try CFBundleIconFile first
        if let iconFileName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            var iconName = iconFileName
            if !iconName.hasSuffix(".icns") {
                iconName += ".icns"
            }
            
            let iconPath = appURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Resources")
                .appendingPathComponent(iconName)
            
            if fileManager.fileExists(atPath: iconPath.path),
               let icon = NSImage(contentsOf: iconPath) {
                logger.debug("Extracted icon from CFBundleIconFile: \(iconName)")
                return icon
            }
        }
        
        // Try CFBundleIconName (for Asset Catalog icons)
        if let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String {
            // Asset catalog icons require different extraction
            // We'll fall back to NSWorkspace for these
            logger.debug("App uses Asset Catalog icon: \(iconName)")
        }
        
        return nil
    }
    
    /// Extract icon using NSWorkspace (works with Asset Catalogs)
    @MainActor
    private func extractUsingWorkspace(appURL: URL, size: Int) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        
        // Resize to desired size for consistency
        let resized = resizeImage(icon, to: NSSize(width: size, height: size))
        
        logger.debug("Extracted icon using NSWorkspace")
        return resized
    }
    
    // MARK: - Icon Conversion
    
    /// Convert an NSImage to ICNS data
    /// - Parameter image: The source image
    /// - Returns: ICNS format data
    func convertToICNS(image: NSImage) throws -> Data {
        // Create multiple representations for the ICNS
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw IconError.conversionFailed("Could not get bitmap representation")
        }
        
        // For simplicity, we'll create a PNG and let macOS handle it
        // Real ICNS creation would require creating iconset folder and using iconutil
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw IconError.conversionFailed("Could not create PNG representation")
        }
        
        return pngData
    }
    
    /// Save image as ICNS file
    /// - Parameters:
    ///   - image: The source image
    ///   - destination: Where to save the ICNS file
    func saveAsICNS(image: NSImage, to destination: URL) async throws {
        logger.debug("Saving ICNS to: \(destination.path)")
        
        // Create a temporary iconset directory
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iconsetPath = tempDir.appendingPathComponent("AppIcon.iconset")
        
        try fileManager.createDirectory(at: iconsetPath, withIntermediateDirectories: true)
        
        defer {
            // Clean up temp directory
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Generate all required sizes
        let iconSizes: [(name: String, size: Int, scale: Int)] = [
            ("icon_16x16", 16, 1),
            ("icon_16x16@2x", 16, 2),
            ("icon_32x32", 32, 1),
            ("icon_32x32@2x", 32, 2),
            ("icon_128x128", 128, 1),
            ("icon_128x128@2x", 128, 2),
            ("icon_256x256", 256, 1),
            ("icon_256x256@2x", 256, 2),
            ("icon_512x512", 512, 1),
            ("icon_512x512@2x", 512, 2),
        ]
        
        for iconSize in iconSizes {
            let pixelSize = iconSize.size * iconSize.scale
            let resized = resizeImage(image, to: NSSize(width: pixelSize, height: pixelSize))
            
            guard let tiffData = resized.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                continue
            }
            
            let filePath = iconsetPath.appendingPathComponent("\(iconSize.name).png")
            try pngData.write(to: filePath)
        }
        
        // Use iconutil to create ICNS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconsetPath.path, "-o", destination.path]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw IconError.iconutilFailed(process.terminationStatus)
        }
        
        logger.info("Successfully created ICNS at: \(destination.path)")
    }
    
    /// Save image as PNG file
    /// - Parameters:
    ///   - image: The source image
    ///   - destination: Where to save the PNG file
    ///   - size: Optional size to resize to
    func saveAsPNG(image: NSImage, to destination: URL, size: Int? = nil) throws {
        var imageToSave = image
        
        if let size = size {
            imageToSave = resizeImage(image, to: NSSize(width: size, height: size))
        }
        
        guard let tiffData = imageToSave.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw IconError.conversionFailed("Could not create PNG")
        }
        
        try pngData.write(to: destination)
        logger.debug("Saved PNG to: \(destination.path)")
    }
    
    // MARK: - Image Manipulation
    
    /// Resize an image to the specified size
    /// - Parameters:
    ///   - image: The source image
    ///   - size: Target size
    /// - Returns: Resized image
    nonisolated func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// Create a badge overlay on an icon
    /// - Parameters:
    ///   - baseIcon: The base icon
    ///   - badge: Badge image or text
    ///   - position: Badge position
    /// - Returns: Icon with badge
    func addBadge(to baseIcon: NSImage, badge: NSImage, position: BadgePosition = .bottomRight) -> NSImage {
        let size = baseIcon.size
        let badgeSize = NSSize(width: size.width * 0.4, height: size.height * 0.4)
        
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        
        // Draw base icon
        baseIcon.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: baseIcon.size),
            operation: .copy,
            fraction: 1.0
        )
        
        // Calculate badge position
        let badgeOrigin: NSPoint
        switch position {
        case .topRight:
            badgeOrigin = NSPoint(x: size.width - badgeSize.width, y: size.height - badgeSize.height)
        case .topLeft:
            badgeOrigin = NSPoint(x: 0, y: size.height - badgeSize.height)
        case .bottomRight:
            badgeOrigin = NSPoint(x: size.width - badgeSize.width, y: 0)
        case .bottomLeft:
            badgeOrigin = NSPoint(x: 0, y: 0)
        }
        
        // Draw badge
        badge.draw(
            in: NSRect(origin: badgeOrigin, size: badgeSize),
            from: NSRect(origin: .zero, size: badge.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        
        return newImage
    }
    
    // MARK: - Custom Icon Loading
    
    /// Load a custom icon from file
    /// - Parameter url: Path to the icon file (PNG, ICNS, JPEG, etc.)
    /// - Returns: NSImage
    func loadCustomIcon(from url: URL) throws -> NSImage {
        guard fileManager.fileExists(atPath: url.path) else {
            throw IconError.fileNotFound(url)
        }
        
        guard let image = NSImage(contentsOf: url) else {
            throw IconError.invalidImageFile(url)
        }
        
        logger.debug("Loaded custom icon from: \(url.path)")
        return image
    }
}

// MARK: - Badge Position

enum BadgePosition {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
}

// MARK: - Errors

enum IconError: LocalizedError {
    case extractionFailed(URL)
    case conversionFailed(String)
    case iconutilFailed(Int32)
    case fileNotFound(URL)
    case invalidImageFile(URL)
    
    var errorDescription: String? {
        switch self {
        case .extractionFailed(let url):
            return "Failed to extract icon from: \(url.path)"
        case .conversionFailed(let message):
            return "Icon conversion failed: \(message)"
        case .iconutilFailed(let code):
            return "iconutil failed with exit code: \(code)"
        case .fileNotFound(let url):
            return "Icon file not found: \(url.path)"
        case .invalidImageFile(let url):
            return "Invalid image file: \(url.path)"
        }
    }
}
