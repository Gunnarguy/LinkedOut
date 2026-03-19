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
    @Published var rejectedJobs: [JobPayload] = []
    @Published var stats: StatsResponse?
    @Published var isLoading = false
    @Published var isIngesting = false
    @Published var isRescoring = false
    @Published var rescoreProgress: String = ""
    @Published var error: String?
    @Published var info: String?

    /// True when the last network request failed — shows offline indicator
    @Published var isOffline = false

    /// The timestamp of the last time the user viewed the Discover tab
    @Published var lastSeenTimestamp: Date = .distantPast

    /// Number of pending jobs newer than lastSeenTimestamp
    var newJobCount: Int {
        pendingJobs.filter { ($0.postedAt ?? .distantPast) > lastSeenTimestamp }.count
    }

    /// Companies the user has blocked (loaded from @AppStorage via SettingsView)
    var blockedCompanies: Set<String> {
        guard let data = UserDefaults.standard.string(forKey: "blockedCompaniesJSON")?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(decoded.map { $0.lowercased() })
    }

    /// Pending jobs with blocked companies and already-decided URLs filtered out
    var visiblePendingJobs: [JobPayload] {
        let blocked = blockedCompanies
        let decided = decidedURLs

        // Filter out acted-upon/blocked jobs
        let rawFilter = pendingJobs.filter { job in
            if !blocked.isEmpty && blocked.contains(job.companyName.lowercased()) { return false }
            if decided.contains(job.sourceUrl) { return false }
            return true
        }

        // Sort explicitly: LLM-scored jobs first, then properly scored jobs by builder_score descending
        return rawFilter.sorted { a, b in
            let aIsLocal = a.aiPitchSummary.lowercased().contains("local keyword")
            let bIsLocal = b.aiPitchSummary.lowercased().contains("local keyword")

            if aIsLocal && !bIsLocal { return false }
            if !aIsLocal && bIsLocal { return true }
            return a.builderScore > b.builderScore
        }
    }

    // MARK: - Local Decided-URLs Tracker
    // Tracks URLs the user has acted on locally, so jobs never resurface
    // even when switching backends (local Docker ↔ Render).

    private static let decidedURLsKey = "decidedJobURLs"

    /// URLs the user has already applied/rejected/saved — persisted in UserDefaults
    private var decidedURLs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.decidedURLsKey) ?? [])
    }

    /// Record a URL as decided so it never shows up again
    private func markURLDecided(_ url: String) {
        var urls = UserDefaults.standard.stringArray(forKey: Self.decidedURLsKey) ?? []
        if !urls.contains(url) {
            urls.append(url)
            // Cap at 5000 to avoid UserDefaults bloat
            if urls.count > 5000 { urls.removeFirst(urls.count - 5000) }
            UserDefaults.standard.set(urls, forKey: Self.decidedURLsKey)
        }
    }

    /// Remove a URL from the decided set (used by undo)
    private func unmarkURLDecided(_ url: String) {
        var urls = UserDefaults.standard.stringArray(forKey: Self.decidedURLsKey) ?? []
        urls.removeAll { $0 == url }
        UserDefaults.standard.set(urls, forKey: Self.decidedURLsKey)
    }

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

    /// Prevents double-swipe race conditions on the same job
    @Published var processingJobIds: Set<String> = []

    /// Queue of actions that failed to sync to the backend — retried on next successful network call
    private var failedActionQueue: [(request: JobActionRequest, retries: Int)] = []

    // MARK: - Console Telemetry

    /// Latest telemetry snapshot (also used by TelemetryView)
    @Published var telemetry: TelemetryResponse?

    private var telemetryTask: Task<Void, Never>?
    private var lastTelemetryLogs: [String] = []

    /// Start polling backend telemetry and printing to Xcode console.
    /// Called once from app startup; safe to call multiple times.
    func startTelemetryLogger() {
        guard telemetryTask == nil else { return }
        print("[TELEM] 🟢 Starting background telemetry logger (10s interval)")
        telemetryTask = Task {
            while !Task.isCancelled {
                await fetchAndLogTelemetry()
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
            }
        }
    }

    func stopTelemetryLogger() {
        telemetryTask?.cancel()
        telemetryTask = nil
        print("[TELEM] 🔴 Telemetry logger stopped")
    }

    /// Single fetch + console print. Can be called on-demand too.
    func fetchAndLogTelemetry() async {
        do {
            let t = try await APIClient.shared.fetchTelemetry(logLines: 80)
            self.telemetry = t
            printTelemetry(t)
            printInterestingTelemetryLogs(t.logs)
        } catch {
            print("[TELEM] ❌ Failed to fetch: \(error.localizedDescription)")
        }
    }

    private func printInterestingTelemetryLogs(_ logs: [String]) {
        let newLogs = newTelemetryLogs(from: logs)
        let interesting = newLogs.filter { line in
            let lower = line.lowercased()
            return lower.contains("[li-")
                || lower.contains("linkedin")
                || lower.contains("oauth")
                || lower.contains("identityme")
                || lower.contains("userinfo")
                || lower.contains("verificationreport")
                || lower.contains("/auth/")
                || lower.contains("/api/profile/resume")
        }

        guard !interesting.isEmpty else { return }

        print("┌─── LINKEDIN BACKEND LOGS ───────────────────────")
        for line in interesting.suffix(12) {
            print("│ \(line)")
        }
        print("└─────────────────────────────────────────────────")
    }

    private func newTelemetryLogs(from logs: [String]) -> [String] {
        guard !lastTelemetryLogs.isEmpty else {
            lastTelemetryLogs = logs
            return logs
        }

        let overlap = telemetryOverlapCount(previous: lastTelemetryLogs, current: logs)
        let newLogs = Array(logs.dropFirst(overlap))
        lastTelemetryLogs = logs
        return newLogs
    }

    private func telemetryOverlapCount(previous: [String], current: [String]) -> Int {
        let maxOverlap = min(previous.count, current.count)
        guard maxOverlap > 0 else { return 0 }

        for count in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(previous.suffix(count)) == Array(current.prefix(count)) {
                return count
            }
        }

        return 0
    }

    private func printTelemetry(_ t: TelemetryResponse) {
        let s = t.server
        let i = t.ingest
        let p = i.progress
        let r = t.rescore
        let st = t.store
        let l = t.llm

        var lines: [String] = []
        lines.append("┌─── TELEMETRY ───────────────────────────────────")
        lines.append("│ 🖥  \(s.hostname):\(s.port)  up \(s.uptimeHuman)  \(s.render ? "☁️ Render" : "🐳 Docker")  debug=\(s.debug)")
        lines.append("│ 📦 Store: \(st.pending)P / \(st.applied)A / \(st.saved)S / \(st.rejected)R  seen=\(st.seenUrls ?? 0)")
        lines.append("│ 🤖 LLM: \(l.provider)  gemini=\(l.hasGeminiKey ? "✅" : "❌")  openai=\(l.hasOpenaiKey ? "✅" : "❌")")

        // Ingest
        let lockIcon = i.lockHeld ? "🔒" : "🔓"
        if p.phase == "idle" || p.phase == "complete" {
            let dur = p.lastDurationS.map { String(format: "%.1fs", $0) } ?? "-"
            lines.append("│ ⚙️ Ingest: \(p.phase)  \(lockIcon)  cycles=\(p.cyclesCompleted)  last=\(dur)")
        } else {
            lines.append("│ ⚙️ Ingest: \(p.phase.uppercased())  \(lockIcon)  batch \(p.batch)/\(p.totalBatches)")
            lines.append("│    fetched=\(p.fetched) new=\(p.newAfterDedup) scored=\(p.scored) queued=\(p.queued) rejected=\(p.rejected) low=\(p.lowScore) err=\(p.errors)")
        }

        // Rescore
        if r.running {
            lines.append("│ 🔄 Rescore: RUNNING \(r.done)/\(r.total)  errors=\(r.errors)")
        } else if r.total > 0 {
            lines.append("│ 🔄 Rescore: done \(r.done)/\(r.total)  errors=\(r.errors)")
        }

        // Notion
        let n = t.notion
        if n.configured {
            var nParts = ["configured"]
            if n.syncTaskAlive { nParts.append("SYNCING") }
            if n.scoreTaskAlive { nParts.append("SCORING") }
            lines.append("│ 📝 Notion: \(nParts.joined(separator: " | "))")
        }

        lines.append("└─────────────────────────────────────────────────")
        print(lines.joined(separator: "\n"))
    }

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
        appliedJobs = Self.readCache("applied") ?? []
        rejectedJobs = Self.readCache("rejected") ?? []
        let total = pendingJobs.count + savedJobs.count + appliedJobs.count + rejectedJobs.count
        if total > 0 {
            print("[BOOT] 💾 Restored from cache: \(pendingJobs.count)P / \(savedJobs.count)S / \(appliedJobs.count)A / \(rejectedJobs.count)R")
        } else {
            print("[BOOT] 💾 No cached jobs found")
        }
        print("[BOOT] 📋 Decided URLs tracked: \(decidedURLs.count)")
        print("[BOOT] 🚫 Blocked companies: \(blockedCompanies.isEmpty ? "none" : blockedCompanies.joined(separator: ", "))")
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
        defer { isLoading = false }
        print("[VM] loadPendingJobs — starting")

        do {
            let fetched = try await APIClient.shared.fetchPendingJobs()
            isOffline = false
            error = nil

            if fetched.isEmpty && !pendingJobs.isEmpty {
                // Server returned 0 but we have cached jobs — keep them
                print("[VM] loadPendingJobs — server returned 0, keeping \(pendingJobs.count) cached jobs")
            } else {
                pendingJobs = fetched
                Self.writeCache("pending", jobs: pendingJobs)
                print("[VM] loadPendingJobs — got \(pendingJobs.count) jobs")
                for (i, j) in pendingJobs.prefix(5).enumerated() {
                    print("[VM]   [\(i)] \(j.roleTitle) @ \(j.companyName) score=\(j.builderScore)")
                }
            }
        } catch {
            print("[VM] loadPendingJobs — ERROR: \(error)")
            isOffline = true
            if pendingJobs.isEmpty {
                self.error = "Can't reach server — check that your Mac is awake and Docker is running"
            } else {
                self.info = "Offline — showing cached jobs"
            }
        }
    }

    func loadAppliedJobs() async {
        print("[VM] loadAppliedJobs — starting")
        do {
            let fetched = try await APIClient.shared.fetchAppliedJobs()
            if fetched.isEmpty && !appliedJobs.isEmpty {
                print("[VM] loadAppliedJobs — server returned 0, keeping \(appliedJobs.count) cached")
            } else {
                appliedJobs = fetched
                Self.writeCache("applied", jobs: appliedJobs)
                print("[VM] loadAppliedJobs — got \(appliedJobs.count)")
            }
        } catch {
            print("[VM] loadAppliedJobs — ERROR (suppressed): \(error)")
        }
    }

    func loadSavedJobs() async {
        print("[VM] loadSavedJobs — starting")
        do {
            let fetched = try await APIClient.shared.fetchSavedJobs()
            if fetched.isEmpty && !savedJobs.isEmpty {
                print("[VM] loadSavedJobs — server returned 0, keeping \(savedJobs.count) cached")
            } else {
                savedJobs = fetched
                Self.writeCache("saved", jobs: savedJobs)
                print("[VM] loadSavedJobs — got \(savedJobs.count)")
            }
        } catch {
            print("[VM] loadSavedJobs — ERROR (suppressed): \(error)")
        }
    }

    func loadRejectedJobs() async {
        print("[VM] loadRejectedJobs — starting")
        do {
            let fetched = try await APIClient.shared.fetchRejectedJobs()
            if fetched.isEmpty && !rejectedJobs.isEmpty {
                print("[VM] loadRejectedJobs — server returned 0, keeping \(rejectedJobs.count) cached")
            } else {
                rejectedJobs = fetched
                Self.writeCache("rejected", jobs: rejectedJobs)
                print("[VM] loadRejectedJobs — got \(rejectedJobs.count)")
            }
        } catch {
            print("[VM] loadRejectedJobs — ERROR (suppressed): \(error)")
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
        print("[VM] refreshAll — reloading all lists + stats")
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

            // Poll for completion — use cycle_active to detect ongoing periodic ingest too
            ingestProgress = "Scanning & scoring with AI..."
            var pollCount = 0
            let maxPolls = 300  // ~10 minutes max (ingest can take 5-10 min)
            while pollCount < maxPolls {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                pollCount += 1

                let status = try await APIClient.shared.fetchIngestStatus()
                let stillActive = status.manualRunning || (status.cycleActive ?? false)

                // Pull live telemetry during ingest for console visibility
                if pollCount % 3 == 0 { // Every ~6s
                    await fetchAndLogTelemetry()
                }

                if !stillActive {
                    // Ingest finished
                    let ingested = status.lastIngestResult ?? 0
                    print("[VM] ingestNewJobs — done after \(pollCount) polls, ingested=\(ingested)")
                    ingestProgress = "Loading results..."
                    pendingJobs = try await APIClient.shared.fetchPendingJobs()
                    print("[VM] ingestNewJobs — pending queue now has \(pendingJobs.count) jobs")
                    await loadStats()

                    // Even if this manual ingest scored 0, the periodic ingest may have
                    // queued jobs while we were waiting for the lock.
                    if pendingJobs.isEmpty && status.store.pending > 0 {
                        print("[VM] ingestNewJobs — store has \(status.store.pending) but fetch returned 0, retrying...")
                        pendingJobs = try await APIClient.shared.fetchPendingJobs()
                    }

                    if ingested == 0 && pendingJobs.isEmpty {
                        print("[VM] ingestNewJobs — zero jobs ingested this round")
                        info = "No new jobs matched your profile this round — try again later"
                    }
                    return
                }

                // Update progress message with live telemetry data
                if let t = telemetry {
                    let p = t.ingest.progress
                    if p.phase == "scoring" && p.totalBatches > 0 {
                        ingestProgress = "Scoring batch \(p.batch)/\(p.totalBatches) — \(p.queued) queued so far"
                    } else if p.phase == "fetching" {
                        ingestProgress = "Fetching from job boards…"
                    } else if p.phase == "deduping" {
                        ingestProgress = "Deduplicating \(p.fetched) listings…"
                    } else if pollCount % 5 == 0 {
                        ingestProgress = "Still scoring... (\(pollCount * 2)s)"
                    }
                } else if pollCount % 5 == 0 {
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
        let visible = visiblePendingJobs.count
        print("[VM] autoIngestIfNeeded — pending=\(pendingJobs.count) visible=\(visible) ingesting=\(isIngesting) loading=\(isLoading) alreadyDone=\(hasAutoIngested)")
        guard pendingJobs.isEmpty && !isIngesting && !isLoading && !hasAutoIngested else {
            print("[VM] autoIngestIfNeeded — skipped (guard failed)")
            return
        }
        hasAutoIngested = true
        print("[VM] autoIngestIfNeeded — queue empty, triggering auto-ingest")
        await ingestNewJobs()
    }

    // MARK: - Rescore

    /// Rescore all pending jobs with updated preferences/profile
    func rescoreAllJobs() async {
        guard !isRescoring else { return }
        isRescoring = true
        rescoreProgress = "Starting rescore..."
        error = nil
        info = nil
        defer {
            isRescoring = false
            rescoreProgress = ""
        }
        print("[VM] rescoreAllJobs — starting")

        do {
            let kickoff = try await APIClient.shared.rescoreJobs(buckets: ["pending"])
            print("[VM] rescoreAllJobs — kickoff status=\(kickoff.status) total=\(kickoff.total ?? 0)")
            let total = kickoff.total ?? 0
            if total == 0 {
                info = "No pending jobs to rescore"
                return
            }

            rescoreProgress = "Rescoring \(total) jobs..."

            // Poll for completion
            var pollCount = 0
            let maxPolls = 300 // ~10 min
            while pollCount < maxPolls {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                pollCount += 1

                let status = try await APIClient.shared.fetchRescoreStatus()
                let done = status.done ?? 0
                let statusTotal = status.total ?? total
                let errors = status.errors ?? 0

                if status.running == true {
                    rescoreProgress = "Rescoring \(done)/\(statusTotal)..."
                    if pollCount % 3 == 0 {
                        await fetchAndLogTelemetry()
                    }
                } else {
                    // Rescore finished
                    print("[VM] rescoreAllJobs — done: \(done)/\(statusTotal), errors=\(errors)")
                    pendingJobs = try await APIClient.shared.fetchPendingJobs()
                    Self.writeCache("pending", jobs: pendingJobs)
                    await loadStats()
                    info = "Rescored \(done) jobs" + (errors > 0 ? " (\(errors) errors)" : "")
                    return
                }
            }

            // Timed out
            print("[VM] rescoreAllJobs — polling timed out")
            pendingJobs = try await APIClient.shared.fetchPendingJobs()
            Self.writeCache("pending", jobs: pendingJobs)
            await loadStats()
            info = "Rescore still running — pull to refresh for latest"
        } catch {
            print("[VM] rescoreAllJobs — ERROR: \(error)")
            self.error = error.localizedDescription
        }
    }

    // MARK: - Swipe Actions

    func swipeRight(job: JobPayload) async {
        guard !processingJobIds.contains(job.id) else { return }
        // Show the "apply" prompt instead of silently moving to applied list
        jobToApply = job
    }

    /// Actually mark the job as applied after the user confirms or dismisses the apply prompt
    func confirmApply(job: JobPayload) async {
        ApplicationTracker.markApplied(jobId: job.id)
        await performAction(job: job, action: .apply)
    }

    func swipeLeft(job: JobPayload) async {
        guard !processingJobIds.contains(job.id) else { return }
        await performAction(job: job, action: .reject)
    }

    func swipeUp(job: JobPayload) async {
        guard !processingJobIds.contains(job.id) else { return }
        await performAction(job: job, action: .save)
    }

    func performAction(job: JobPayload, action: JobAction) async {
        let jobId = job.id
        guard !processingJobIds.contains(jobId) else { return }
        print("[VM] performAction — \(action.rawValue) on \(jobId)")
        processingJobIds.insert(jobId)

        // Optimistic removal — prevents card flash-back after swipe animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            pendingJobs.removeAll { $0.id == jobId }

            // Instantly update target list for snappy offline/local UX
            switch action {
            case .apply:
                appliedJobs.insert(job, at: 0)
                Self.writeCache("applied", jobs: appliedJobs)
            case .save:
                savedJobs.insert(job, at: 0)
                Self.writeCache("saved", jobs: savedJobs)
            case .reject:
                rejectedJobs.insert(job, at: 0)
                Self.writeCache("rejected", jobs: rejectedJobs)
            }

            Self.writeCache("pending", jobs: pendingJobs)
        }

        // Mark instantly so it never comes back
        recordAction(job: job, action: action)
        markURLDecided(job.sourceUrl)

        // Fire-and-forget network sync — queues for retry on failure
        Task.detached {
            let request = JobActionRequest(jobId: jobId, action: action, jobData: job)
            do {
                let response = try await APIClient.shared.performAction(request)
                print("[VM] background performAction — success=\(response.success) msg=\(response.message)")
                if response.success {
                    await self.loadStats()
                    // Drain any previously failed actions now that the network is back
                    await self.retryFailedActions()
                } else {
                    print("[VM] background server rejected action on \(jobId)")
                }
            } catch {
                print("[VM] background performAction failed — \(error.localizedDescription) — queued for retry")
                await MainActor.run {
                    self.failedActionQueue.append((request: request, retries: 0))
                }
            }

            await MainActor.run {
                _ = self.processingJobIds.remove(jobId)
            }
        }
    }

    /// Remove a job from all local lists when the server says it's gone
    private func purgeStaleJob(id: String) {
        print("[VM] purgeStaleJob — removing \(id) from all lists")
        withAnimation {
            pendingJobs.removeAll { $0.id == id }
            appliedJobs.removeAll { $0.id == id }
            savedJobs.removeAll { $0.id == id }
            if selectedJob?.id == id { selectedJob = nil }
            Self.writeCache("pending", jobs: pendingJobs)
            Self.writeCache("applied", jobs: appliedJobs)
            Self.writeCache("saved", jobs: savedJobs)
        }
    }

    /// Retry any queued actions that previously failed to sync
    private func retryFailedActions() async {
        guard !failedActionQueue.isEmpty else { return }
        let queue = await MainActor.run { () -> [(request: JobActionRequest, retries: Int)] in
            let q = self.failedActionQueue
            self.failedActionQueue.removeAll()
            return q
        }
        for item in queue {
            do {
                let response = try await APIClient.shared.performAction(item.request)
                if response.success {
                    print("[VM] retry succeeded for \(item.request.jobId)")
                } else {
                    print("[VM] retry rejected by server for \(item.request.jobId)")
                }
            } catch {
                // Re-queue if under 3 retries
                if item.retries < 3 {
                    print("[VM] retry failed for \(item.request.jobId) — re-queuing (attempt \(item.retries + 1))")
                    await MainActor.run {
                        self.failedActionQueue.append((request: item.request, retries: item.retries + 1))
                    }
                } else {
                    print("[VM] retry exhausted for \(item.request.jobId) — dropping")
                }
            }
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

    /// Tracks recent actions for multi-undo (local mirror of backend's 20-deep stack)
    struct RecentAction: Identifiable {
        let id = UUID()
        let jobId: String
        let jobTitle: String
        let sourceUrl: String
        let action: JobAction
        let timestamp: Date
    }

    @Published var recentActions: [RecentAction] = []

    /// How many actions can be undone
    var undoCount: Int { recentActions.count }

    /// Record a local action for undo tracking
    func recordAction(job: JobPayload, action: JobAction) {
        recentActions.append(RecentAction(
            jobId: job.id,
            jobTitle: job.roleTitle,
            sourceUrl: job.sourceUrl,
            action: action,
            timestamp: Date()
        ))
        // Keep in sync with backend's 20-deep limit
        if recentActions.count > 20 {
            recentActions.removeFirst()
        }
    }

    func undoLastAction() async {
        guard !recentActions.isEmpty else {
            print("[VM] undo — nothing to undo")
            self.error = "Nothing to undo"
            return
        }
        print("[VM] undo — requesting undo from backend...")
        do {
            let result = try await APIClient.shared.undoLastAction()
            if result.success {
                let undone = recentActions.removeLast()
                unmarkURLDecided(undone.sourceUrl)
                print("[VM] undo — success: \(undone.action.rawValue) on \(undone.jobTitle)")
                info = "Undid \(undone.action.rawValue) on \(undone.jobTitle)"
                await refreshAll()
            } else {
                print("[VM] undo — server rejected: \(result.message)")
                self.error = result.message
            }
        } catch {
            print("[VM] undo — failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    // MARK: - Notes & Status

    func updateNotes(jobId: String, notes: String) async {
        print("[VM] updateNotes — jobId=\(jobId) notes=\(notes.prefix(30))...")
        do {
            let updated = try await APIClient.shared.updateJobNotes(jobId: jobId, notes: notes)
            replaceJobInLists(updated)
            print("[VM] updateNotes — success")
        } catch let apiError as APIError where apiError.is404 {
            print("[VM] updateNotes — 404, purging stale job \(jobId)")
            purgeStaleJob(id: jobId)
            self.error = "That job is no longer on the server"
        } catch {
            print("[VM] updateNotes — failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    func updateStatus(jobId: String, status: String) async {
        print("[VM] updateStatus — jobId=\(jobId) status=\(status)")
        do {
            let updated = try await APIClient.shared.updateJobStatus(jobId: jobId, status: status)
            replaceJobInLists(updated)
            print("[VM] updateStatus — success")
        } catch let apiError as APIError where apiError.is404 {
            print("[VM] updateStatus — 404, purging stale job \(jobId)")
            purgeStaleJob(id: jobId)
            self.error = "That job is no longer on the server"
        } catch {
            print("[VM] updateStatus — failed: \(error.localizedDescription)")
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
