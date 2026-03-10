//
//  JobsViewModel.swift
//  LinkedOut
//
//  Manages job pipeline state — pending, applied, saved.
//

import Combine
import Foundation
import SwiftUI

@MainActor
class JobsViewModel: ObservableObject {
    @Published var pendingJobs: [JobPayload] = []
    @Published var appliedJobs: [JobPayload] = []
    @Published var savedJobs: [JobPayload] = []
    @Published var stats: StatsResponse?
    @Published var isLoading = false
    @Published var isIngesting = false
    @Published var error: String?

    /// The job currently being viewed in detail
    @Published var selectedJob: JobPayload?

    /// Track swipe animation
    @Published var topCardOffset: CGSize = .zero
    @Published var topCardRotation: Double = 0

    func loadPendingJobs() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            pendingJobs = try await APIClient.shared.fetchPendingJobs()
            if pendingJobs.isEmpty {
                // Auto-seed on first load for dev
                _ = try? await APIClient.shared.seedMockData()
                pendingJobs = try await APIClient.shared.fetchPendingJobs()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadAppliedJobs() async {
        do {
            appliedJobs = try await APIClient.shared.fetchAppliedJobs()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadSavedJobs() async {
        do {
            savedJobs = try await APIClient.shared.fetchSavedJobs()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadStats() async {
        stats = try? await APIClient.shared.fetchStats()
    }

    func refreshAll() async {
        await loadPendingJobs()
        await loadAppliedJobs()
        await loadSavedJobs()
        await loadStats()
    }

    /// Trigger a fresh job ingest cycle from APIs → LLM scoring → queue
    func ingestNewJobs() async {
        isIngesting = true
        error = nil
        defer { isIngesting = false }

        do {
            let result = try await APIClient.shared.refreshIngest()
            // Reload pending after ingest
            pendingJobs = try await APIClient.shared.fetchPendingJobs()
            await loadStats()
            if result.ingested == 0 {
                error = "No new jobs passed the AI filter this round"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Swipe Actions

    func swipeRight() async {
        guard let job = pendingJobs.first else { return }
        await performAction(jobId: job.id, action: .apply)
    }

    func swipeLeft() async {
        guard let job = pendingJobs.first else { return }
        await performAction(jobId: job.id, action: .reject)
    }

    func swipeUp() async {
        guard let job = pendingJobs.first else { return }
        await performAction(jobId: job.id, action: .save)
    }

    func performAction(jobId: String, action: JobAction) async {
        let request = JobActionRequest(jobId: jobId, action: action)
        do {
            let response = try await APIClient.shared.performAction(request)
            if response.success {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    pendingJobs.removeAll { $0.id == jobId }
                }
                // Refresh the relevant list
                switch action {
                case .apply:
                    await loadAppliedJobs()
                case .save:
                    await loadSavedJobs()
                case .reject:
                    break
                }
                await loadStats()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Card Gesture

    func resetCardPosition() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            topCardOffset = .zero
            topCardRotation = 0
        }
    }

    var swipeHint: SwipeHint {
        if topCardOffset.width > 60 { return .apply }
        if topCardOffset.width < -60 { return .reject }
        if topCardOffset.height < -60 { return .save }
        return .none
    }

    enum SwipeHint {
        case none, apply, reject, save
    }
}
