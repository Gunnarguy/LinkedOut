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
    @Published var info: String?

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

    // MARK: - Disk Cache

    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkedOut", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Load cached jobs from disk immediately (no network).
    func loadCachedJobs() {
        pendingJobs = Self.readCache("pending") ?? []
        savedJobs = Self.readCache("saved") ?? []
        if !pendingJobs.isEmpty {
            print("[VM] loadCachedJobs — restored \(pendingJobs.count) pending, \(savedJobs.count) saved from cache")
        }
    }

    private static func readCache(_ name: String) -> [JobPayload]? {
        let file = cacheDir.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([JobPayload].self, from: data)
    }

    private static func writeCache(_ name: String, jobs: [JobPayload]) {
        let file = cacheDir.appendingPathComponent("\(name).json")
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: file, options: .atomic)
    }

    func loadPendingJobs() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        print("[VM] loadPendingJobs — starting")

        do {
            pendingJobs = try await APIClient.shared.fetchPendingJobs()
            Self.writeCache("pending", jobs: pendingJobs)
            print("[VM] loadPendingJobs — got \(pendingJobs.count) jobs")
            for (i, j) in pendingJobs.prefix(5).enumerated() {
                print("[VM]   [\(i)] \(j.roleTitle) @ \(j.companyName) score=\(j.builderScore)")
            }
        } catch {
            print("[VM] loadPendingJobs — ERROR: \(error)")
            self.error = error.localizedDescription
        }
    }

    func loadAppliedJobs() async {
        print("[VM] loadAppliedJobs — starting")
        do {
            appliedJobs = try await APIClient.shared.fetchAppliedJobs()
            print("[VM] loadAppliedJobs — got \(appliedJobs.count)")
        } catch {
            print("[VM] loadAppliedJobs — ERROR (suppressed): \(error)")
        }
    }

    func loadSavedJobs() async {
        print("[VM] loadSavedJobs — starting")
        do {
            savedJobs = try await APIClient.shared.fetchSavedJobs()
            Self.writeCache("saved", jobs: savedJobs)
            print("[VM] loadSavedJobs — got \(savedJobs.count)")
        } catch {
            print("[VM] loadSavedJobs — ERROR (suppressed): \(error)")
        }
    }

    func loadStats() async {
        statsLoading = true
        defer { statsLoading = false }
        print("[VM] loadStats — starting")
        do {
            stats = try await APIClient.shared.fetchStats()
            if let s = stats {
                print("[VM] loadStats — pending=\(s.pending) applied=\(s.applied) saved=\(s.saved) rejected=\(s.rejected)")
            }
        } catch {
            // Stats are non-critical — don't show red banner for this
            print("[VM] loadStats — ERROR (suppressed): \(error)")
        }
    }

    /// Dismiss the current error banner
    func dismissError() {
        withAnimation { error = nil }
    }

    /// Dismiss the current info banner
    func dismissInfo() {
        withAnimation { info = nil }
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
        info = nil
        ingestProgress = "Fetching jobs from boards..."
        defer {
            isIngesting = false
            ingestProgress = ""
        }
        print("[VM] ingestNewJobs — starting ingest cycle")

        do {
            // Kick off ingest (returns immediately — backend runs it in background)
            print("[VM] ingestNewJobs — calling /api/ingest/refresh...")
            let kickoff = try await APIClient.shared.refreshIngest()
            print("[VM] ingestNewJobs — kickoff status=\(kickoff.status ?? "nil")")

            // Poll for completion
            ingestProgress = "Scanning & scoring with AI..."
            var pollCount = 0
            let maxPolls = 120  // ~4 minutes max
            while pollCount < maxPolls {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                pollCount += 1

                let status = try await APIClient.shared.fetchIngestStatus()
                if !status.manualRunning {
                    // Ingest finished
                    let ingested = status.lastIngestResult ?? 0
                    print("[VM] ingestNewJobs — done after \(pollCount) polls, ingested=\(ingested)")
                    ingestProgress = "Loading results..."
                    pendingJobs = try await APIClient.shared.fetchPendingJobs()
                    print("[VM] ingestNewJobs — pending queue now has \(pendingJobs.count) jobs")
                    await loadStats()
                    if ingested == 0 {
                        print("[VM] ingestNewJobs — zero jobs ingested this round")
                        info = "No new jobs matched your profile this round — try again later"
                    }
                    return
                }

                // Update progress message
                if pollCount % 5 == 0 {
                    ingestProgress = "Still scoring... (\(pollCount * 2)s)"
                }
            }

            // Timed out polling — still load what we have
            print("[VM] ingestNewJobs — polling timed out, loading current state")
            pendingJobs = try await APIClient.shared.fetchPendingJobs()
            await loadStats()
            info = "Scoring is still running — pull to refresh for latest results"

        } catch {
            print("[VM] ingestNewJobs — ERROR: \(error)")
            self.error = error.localizedDescription
        }
    }

    /// Auto-ingest once per session when the queue loads empty
    func autoIngestIfNeeded() async {
        print("[VM] autoIngestIfNeeded — pending=\(pendingJobs.count) ingesting=\(isIngesting) loading=\(isLoading) alreadyDone=\(hasAutoIngested)")
        guard pendingJobs.isEmpty && !isIngesting && !isLoading && !hasAutoIngested else {
            print("[VM] autoIngestIfNeeded — skipped (guard failed)")
            return
        }
        hasAutoIngested = true
        print("[VM] autoIngestIfNeeded — queue empty, triggering auto-ingest")
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
        print("[VM] performAction — \(action.rawValue) on \(jobId)")
        let request = JobActionRequest(jobId: jobId, action: action)
        do {
            let response = try await APIClient.shared.performAction(request)
            print("[VM] performAction — success=\(response.success) msg=\(response.message)")
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
