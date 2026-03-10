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
        do {
            stats = try await APIClient.shared.fetchStats()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Dismiss the current error banner
    func dismissError() {
        withAnimation { error = nil }
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

    // MARK: - Undo

    func undoLastAction() async {
        do {
            let result = try await APIClient.shared.undoLastAction()
            if result.success {
                await refreshAll()
            } else {
                self.error = result.message
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Notes & Status

    func updateNotes(jobId: String, notes: String) async {
        do {
            let updated = try await APIClient.shared.updateJobNotes(jobId: jobId, notes: notes)
            replaceJobInLists(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateStatus(jobId: String, status: String) async {
        do {
            let updated = try await APIClient.shared.updateJobStatus(jobId: jobId, status: status)
            replaceJobInLists(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Replace a job in all local lists after an update
    private func replaceJobInLists(_ job: JobPayload) {
        if let idx = pendingJobs.firstIndex(where: { $0.id == job.id }) {
            pendingJobs[idx] = job
        }
        if let idx = appliedJobs.firstIndex(where: { $0.id == job.id }) {
            appliedJobs[idx] = job
        }
        if let idx = savedJobs.firstIndex(where: { $0.id == job.id }) {
            savedJobs[idx] = job
        }
        if selectedJob?.id == job.id {
            selectedJob = job
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
