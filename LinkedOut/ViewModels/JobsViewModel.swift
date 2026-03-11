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

    /// The job the user wants to apply to after swiping right
    @Published var jobToApply: JobPayload?

    /// Ingest progress message shown during scanning
    @Published var ingestProgress: String = ""

    /// Whether we've already auto-triggered ingest this session
    @Published var hasAutoIngested = false

    /// Whether stats are currently being fetched
    @Published var statsLoading = false

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
        statsLoading = true
        defer { statsLoading = false }
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
        ingestProgress = "Fetching jobs from boards..."
        defer {
            isIngesting = false
            ingestProgress = ""
        }

        do {
            ingestProgress = "Scanning & scoring with AI..."
            let result = try await APIClient.shared.refreshIngest()
            ingestProgress = "Loading results..."
            pendingJobs = try await APIClient.shared.fetchPendingJobs()
            await loadStats()
            if result.ingested == 0 {
                error = "No new jobs passed the AI filter this round"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Auto-ingest once per session when the queue loads empty
    func autoIngestIfNeeded() async {
        guard pendingJobs.isEmpty && !isIngesting && !isLoading && !hasAutoIngested else { return }
        hasAutoIngested = true
        await ingestNewJobs()
    }

    // MARK: - Swipe Actions

    func swipeRight() async {
        guard let job = pendingJobs.first else { return }
        // Show the "apply" prompt instead of silently moving to applied list
        jobToApply = job
    }

    /// Actually mark the job as applied after the user confirms or dismisses the apply prompt
    func confirmApply(job: JobPayload) async {
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
        } catch let apiError as APIError where apiError.is404 {
            // Job no longer exists on server — purge it locally
            purgeStaleJob(id: jobId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Remove a job from all local lists when the server says it's gone
    private func purgeStaleJob(id: String) {
        withAnimation {
            pendingJobs.removeAll { $0.id == id }
            appliedJobs.removeAll { $0.id == id }
            savedJobs.removeAll { $0.id == id }
            if selectedJob?.id == id { selectedJob = nil }
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
        } catch let apiError as APIError where apiError.is404 {
            purgeStaleJob(id: jobId)
            self.error = "That job is no longer on the server"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateStatus(jobId: String, status: String) async {
        do {
            let updated = try await APIClient.shared.updateJobStatus(jobId: jobId, status: status)
            replaceJobInLists(updated)
        } catch let apiError as APIError where apiError.is404 {
            purgeStaleJob(id: jobId)
            self.error = "That job is no longer on the server"
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

    /// The job currently being viewed in detail — shared across tabs
    @Published var selectedJob: JobPayload?

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
