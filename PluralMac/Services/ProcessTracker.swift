//
//  ProcessTracker.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import AppKit
import OSLog
import Combine

/// Tracks running instances launched by PluralMac
@MainActor
final class ProcessTracker: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ProcessTracker()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "ProcessTracker")
    
    /// Map of instance IDs to their running applications
    @Published private(set) var runningInstances: [UUID: NSRunningApplication] = [:]
    
    /// Workspace notification observer
    private var terminationObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    private init() {
        setupTerminationObserver()
    }
    
    deinit {
        if let observer = terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    // MARK: - Setup
    
    private func setupTerminationObserver() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            
            Task { @MainActor in
                self?.handleAppTermination(app)
            }
        }
    }
    
    private func handleAppTermination(_ app: NSRunningApplication) {
        // Find and remove the terminated instance
        for (instanceId, runningApp) in runningInstances {
            if runningApp.processIdentifier == app.processIdentifier {
                runningInstances.removeValue(forKey: instanceId)
                logger.info("Instance terminated: \(instanceId)")
                
                // Post notification
                NotificationCenter.default.post(
                    name: .instanceDidTerminate,
                    object: nil,
                    userInfo: ["instanceId": instanceId]
                )
                break
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Track a launched instance
    /// - Parameters:
    ///   - instanceId: The UUID of the instance
    ///   - app: The running application
    func track(instanceId: UUID, app: NSRunningApplication) {
        runningInstances[instanceId] = app
        logger.info("Now tracking instance: \(instanceId) (PID: \(app.processIdentifier))")
        
        // Post notification
        NotificationCenter.default.post(
            name: .instanceDidLaunch,
            object: nil,
            userInfo: ["instanceId": instanceId, "pid": app.processIdentifier]
        )
    }
    
    /// Check if an instance is currently running
    /// - Parameter instanceId: The UUID of the instance
    /// - Returns: true if the instance is running
    func isRunning(_ instanceId: UUID) -> Bool {
        guard let app = runningInstances[instanceId] else {
            return false
        }
        
        // Verify it's still running
        if app.isTerminated {
            runningInstances.removeValue(forKey: instanceId)
            return false
        }
        
        return true
    }
    
    /// Get the running application for an instance
    /// - Parameter instanceId: The UUID of the instance
    /// - Returns: The NSRunningApplication if running
    func runningApp(for instanceId: UUID) -> NSRunningApplication? {
        guard let app = runningInstances[instanceId], !app.isTerminated else {
            runningInstances.removeValue(forKey: instanceId)
            return nil
        }
        return app
    }
    
    /// Get the process ID for a running instance
    /// - Parameter instanceId: The UUID of the instance
    /// - Returns: The PID if running
    func processId(for instanceId: UUID) -> pid_t? {
        runningApp(for: instanceId)?.processIdentifier
    }
    
    /// Terminate a running instance
    /// - Parameter instanceId: The UUID of the instance to terminate
    /// - Returns: true if termination was initiated successfully
    @discardableResult
    func terminate(_ instanceId: UUID) -> Bool {
        guard let app = runningApp(for: instanceId) else {
            logger.warning("Cannot terminate: instance \(instanceId) not running")
            return false
        }
        
        logger.info("Terminating instance: \(instanceId) (PID: \(app.processIdentifier))")
        
        // Try graceful termination first
        let success = app.terminate()
        
        if success {
            logger.info("Termination initiated for instance: \(instanceId)")
        } else {
            logger.warning("Failed to terminate instance: \(instanceId)")
        }
        
        return success
    }
    
    /// Force terminate a running instance (SIGKILL)
    /// - Parameter instanceId: The UUID of the instance to force terminate
    /// - Returns: true if force termination was initiated
    @discardableResult
    func forceTerminate(_ instanceId: UUID) -> Bool {
        guard let app = runningApp(for: instanceId) else {
            logger.warning("Cannot force terminate: instance \(instanceId) not running")
            return false
        }
        
        logger.info("Force terminating instance: \(instanceId) (PID: \(app.processIdentifier))")
        
        let success = app.forceTerminate()
        
        if success {
            runningInstances.removeValue(forKey: instanceId)
            logger.info("Force termination successful for instance: \(instanceId)")
        }
        
        return success
    }
    
    /// Terminate all running instances
    func terminateAll() {
        logger.info("Terminating all running instances")
        
        for instanceId in runningInstances.keys {
            terminate(instanceId)
        }
    }
    
    /// Activate (bring to front) a running instance
    /// - Parameter instanceId: The UUID of the instance
    /// - Returns: true if activation was successful
    @discardableResult
    func activate(_ instanceId: UUID) -> Bool {
        guard let app = runningApp(for: instanceId) else {
            return false
        }
        
        return app.activate(options: [.activateIgnoringOtherApps])
    }
    
    /// Hide a running instance
    /// - Parameter instanceId: The UUID of the instance
    /// - Returns: true if hide was successful
    @discardableResult
    func hide(_ instanceId: UUID) -> Bool {
        guard let app = runningApp(for: instanceId) else {
            return false
        }
        
        return app.hide()
    }
    
    /// Get count of running instances
    var runningCount: Int {
        // Clean up terminated apps first
        for (id, app) in runningInstances where app.isTerminated {
            runningInstances.removeValue(forKey: id)
        }
        return runningInstances.count
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let instanceDidLaunch = Notification.Name("com.mtech.PluralMac.instanceDidLaunch")
    static let instanceDidTerminate = Notification.Name("com.mtech.PluralMac.instanceDidTerminate")
}
