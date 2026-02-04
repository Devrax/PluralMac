//
//  IconCache.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import AppKit
import OSLog

/// In-memory and disk cache for extracted application icons.
actor IconCache {
    
    // MARK: - Singleton
    
    static let shared = IconCache()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "IconCache")
    private let fileManager = FileManager.default
    
    /// In-memory cache
    private var memoryCache: [String: CachedIcon] = [:]
    
    /// Maximum number of icons in memory cache
    private let maxMemoryCacheSize = 50
    
    /// Disk cache directory
    private var cacheDirectory: URL {
        AppInstance.defaultBaseDirectory
            .appendingPathComponent("Cache")
            .appendingPathComponent("Icons")
    }
    
    // MARK: - Initialization
    
    private init() {
        // Create cache directory if needed
        Task {
            await ensureCacheDirectoryExists()
        }
    }
    
    // MARK: - Cache Operations
    
    /// Get icon from cache
    /// - Parameter appURL: The application URL (used as cache key)
    /// - Returns: Cached icon if available
    func get(for appURL: URL) -> NSImage? {
        let key = cacheKey(for: appURL)
        
        // Check memory cache first
        if let cached = memoryCache[key], !cached.isExpired {
            logger.debug("Memory cache hit for: \(appURL.lastPathComponent)")
            return cached.image
        }
        
        // Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            // Add to memory cache
            memoryCache[key] = CachedIcon(image: diskImage)
            logger.debug("Disk cache hit for: \(appURL.lastPathComponent)")
            return diskImage
        }
        
        return nil
    }
    
    /// Store icon in cache
    /// - Parameters:
    ///   - image: The icon image
    ///   - appURL: The application URL (used as cache key)
    func set(_ image: NSImage, for appURL: URL) {
        let key = cacheKey(for: appURL)
        
        // Store in memory
        memoryCache[key] = CachedIcon(image: image)
        
        // Store on disk
        saveToDisk(image: image, key: key)
        
        // Evict old entries if needed
        evictIfNeeded()
        
        logger.debug("Cached icon for: \(appURL.lastPathComponent)")
    }
    
    /// Remove icon from cache
    /// - Parameter appURL: The application URL
    func remove(for appURL: URL) {
        let key = cacheKey(for: appURL)
        
        // Remove from memory
        memoryCache.removeValue(forKey: key)
        
        // Remove from disk
        let diskPath = cacheDirectory.appendingPathComponent("\(key).png")
        try? fileManager.removeItem(at: diskPath)
        
        logger.debug("Removed cached icon for: \(appURL.lastPathComponent)")
    }
    
    /// Clear all cached icons
    func clearAll() {
        // Clear memory
        memoryCache.removeAll()
        
        // Clear disk
        if let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in contents {
                try? fileManager.removeItem(at: file)
            }
        }
        
        logger.info("Cleared all cached icons")
    }
    
    /// Get the total size of the disk cache
    func diskCacheSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for file in contents {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        
        return totalSize
    }
    
    /// Get the number of cached icons
    func cachedIconCount() -> Int {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        
        return contents.filter { $0.pathExtension == "png" }.count
    }
    
    // MARK: - Private Methods
    
    private func ensureCacheDirectoryExists() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
        }
    }
    
    private func cacheKey(for appURL: URL) -> String {
        // Use bundle identifier if available, otherwise use path hash
        if let bundle = Bundle(url: appURL),
           let bundleId = bundle.bundleIdentifier {
            return bundleId.replacingOccurrences(of: ".", with: "_")
        }
        
        return String(appURL.path.hashValue)
    }
    
    private func loadFromDisk(key: String) -> NSImage? {
        let filePath = cacheDirectory.appendingPathComponent("\(key).png")
        
        guard fileManager.fileExists(atPath: filePath.path) else {
            return nil
        }
        
        return NSImage(contentsOf: filePath)
    }
    
    private func saveToDisk(image: NSImage, key: String) {
        Task {
            await ensureCacheDirectoryExists()
        }
        
        let filePath = cacheDirectory.appendingPathComponent("\(key).png")
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        
        try? pngData.write(to: filePath)
    }
    
    private func evictIfNeeded() {
        guard memoryCache.count > maxMemoryCacheSize else { return }
        
        // Remove oldest entries
        let sortedKeys = memoryCache.sorted { $0.value.timestamp < $1.value.timestamp }
        let keysToRemove = sortedKeys.prefix(memoryCache.count - maxMemoryCacheSize)
        
        for (key, _) in keysToRemove {
            memoryCache.removeValue(forKey: key)
        }
        
        logger.debug("Evicted \(keysToRemove.count) icons from memory cache")
    }
}

// MARK: - Cached Icon

private struct CachedIcon {
    let image: NSImage
    let timestamp: Date
    
    /// Cache expiration time (1 hour)
    static let expirationInterval: TimeInterval = 3600
    
    init(image: NSImage) {
        self.image = image
        self.timestamp = Date()
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > Self.expirationInterval
    }
}
