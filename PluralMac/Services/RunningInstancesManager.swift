//
//  RunningInstancesManager.swift
//  PluralMac
//
//  Created by Rafael Alexander Mejia Blanco on 4/2/26.
//

import Foundation
import Combine
import OSLog

/// Observable manager for tracking running instances.
/// This provides a reactive way for SwiftUI views to know which instances are running.
@MainActor
final class RunningInstancesManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = RunningInstancesManager()
    
    // MARK: - Properties
    
    /// Set of running instance IDs
    @Published private(set) var runningInstanceIds: Set<UUID> = []
    
    private let logger = Logger(subsystem: "com.mtech.PluralMac", category: "RunningInstancesManager")
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {
        setupNotifications()
        startRefreshTimer()
    }
    
    // MARK: - Public Methods
    
    /// Check if an instance is running
    func isRunning(_ instanceId: UUID) -> Bool {
        runningInstanceIds.contains(instanceId)
    }
    
    /// Mark an instance as running
    func markRunning(_ instanceId: UUID) {
        runningInstanceIds.insert(instanceId)
        logger.debug("Marked instance \(instanceId.uuidString) as running")
    }
    
    /// Mark an instance as stopped
    func markStopped(_ instanceId: UUID) {
        runningInstanceIds.remove(instanceId)
        logger.debug("Marked instance \(instanceId.uuidString) as stopped")
    }
    
    /// Refresh running status from DirectLauncher
    func refresh() async {
        let runningIds = await DirectLauncher.shared.runningInstanceIds()
        runningInstanceIds = Set(runningIds)
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        // Listen for termination notifications
        NotificationCenter.default.publisher(for: .instanceTerminated)
            .compactMap { $0.userInfo?["instanceId"] as? UUID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] instanceId in
                self?.markStopped(instanceId)
            }
            .store(in: &cancellables)
        
        // Listen for launch notifications
        NotificationCenter.default.publisher(for: .instanceLaunched)
            .compactMap { $0.userInfo?["instanceId"] as? UUID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] instanceId in
                self?.markRunning(instanceId)
            }
            .store(in: &cancellables)
    }
    
    private func startRefreshTimer() {
        // Refresh every 2 seconds to catch any missed state changes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
}
