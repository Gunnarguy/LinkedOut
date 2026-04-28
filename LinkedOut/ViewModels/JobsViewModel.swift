//
//  JobsViewModel.swift
//  LinkedOut
//
//  Manages job pipeline state — pending, applied, saved.
//

import Combine
import Foundation
import SwiftUI

enum JobSortMode: String, CaseIterable, Identifiable {
    case score = "Best Match"
    case newest = "Newest"
    case salary = "Highest Pay"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .score: return "star.fill"
        case .newest: return "clock.fill"
        case .salary: return "dollarsign.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .score: return .blue
        case .newest: return .orange
        case .salary: return .green
        }
    }
}

enum HeuristicRecoveryMode {
    case onDevice
    case cloud

    var icon: String {
        switch self {
        case .onDevice:
            return "iphone"
        case .cloud:
            return "icloud"
        }
    }

    var tint: Color {
        switch self {
        case .onDevice:
            return .green
        case .cloud:
            return .blue
        }
    }
}

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
    @Published var locallyFilteredPendingCount = 0
    @Published var isRecoveringHeuristicJobs = false
    @Published var heuristicRecoveryBannerMessage: String?
    @Published var heuristicRecoveryMode: HeuristicRecoveryMode?

    /// Generation counter — incremented on every resetLocalJobState(). Fetches that
    /// started before the latest reset are stale and their results must be discarded.
    private var fetchGeneration: Int = 0
    private var lastHeuristicRecoveryAttempt: Date = .distantPast

    private var currentServerURL: String {
        BackendConfig.storedServerURL()
    }

    private var currentBackendLabel: String {
        BackendConfig.backendLabel(for: currentServerURL)
    }

    private var heuristicRecoveryCooldown: TimeInterval { 180 }

    // MARK: - LinkedIn Social State
    @Published var linkedInPosts: [LinkedInPost] = []
    @Published var linkedInComments: [String: [LinkedInComment]] = [:] // post_urn -> comments
    @Published var linkedInReactions: [String: [LinkedInReaction]] = [:] // post_urn -> reactions
    @Published var isSocialLoading = false
    @Published var socialError: String?

    /// How the pending queue is sorted — persisted across sessions
    @Published var sortMode: JobSortMode = .score

    /// The timestamp of the last time the user viewed the Discover tab
    @Published var lastSeenTimestamp: Date = .distantPast

    /// Number of pending jobs newer than lastSeenTimestamp
    var newJobCount: Int {
        visiblePendingJobs.filter { ($0.postedAt ?? .distantPast) > lastSeenTimestamp }.count
    }

    private func portfolioFirstGuardrail(_ jobs: [JobPayload]) -> (kept: [JobPayload], dropped: Int) {
        let kept = jobs.filter { shouldKeepPendingJob($0) }
        return (kept, max(jobs.count - kept.count, 0))
    }

    private func shouldKeepPendingJob(_ job: JobPayload) -> Bool {
        let textBlob = [
            job.roleTitle,
            job.companyName,
            job.location,
            job.description ?? "",
            job.companyDescription ?? "",
            job.whyInteresting ?? "",
            job.jobSnapshot ?? "",
            job.logicFit ?? "",
            (job.fitReasons ?? []).joined(separator: " "),
            (job.tags).joined(separator: " "),
            (job.techStack ?? []).joined(separator: " "),
        ].joined(separator: " ").lowercased()

        let title = job.roleTitle.lowercased()

        let practitionerTitleTerms = [
            "licensed master social worker",
            "social worker",
            "therapist",
            "counselor",
            "registered nurse",
            "nurse practitioner",
            "physician assistant",
            "pharmacist",
            "medical science liaison",
            "case manager",
            "care manager",
        ]

        func containsAny(_ terms: [String], in text: String) -> Bool {
            terms.contains { text.contains($0) }
        }

        func countMatches(_ terms: [String], in text: String) -> Int {
            terms.reduce(into: 0) { count, term in
                if text.contains(term) { count += 1 }
            }
        }

        if containsAny(practitionerTitleTerms, in: title) {
            return false
        }

        let hardRejectTitleTerms = [
            "senior engineer",
            "senior software engineer",
            "senior backend engineer",
            "senior platform engineer",
            "staff engineer",
            "principal engineer",
            "lead engineer",
            "lead software engineer",
            "engineering manager",
            "director of engineering",
            "head of engineering",
            "platform engineer",
            "infrastructure engineer",
            "site reliability engineer",
            "full-stack engineer",
            "full stack engineer",
            "full-stack software engineer",
            "full-stack developer",
            "backend engineer",
            "backend developer",
            "machine learning engineer",
            "ml engineer",
            "security engineer",
            "sales engineer",
        ]

        let strongTargetTitleTerms = [
            "forward deployed engineer",
            "forward-deployed engineer",
            "solutions engineer",
            "technical solutions engineer",
            "clinical solutions engineer",
            "implementation engineer",
            "technical implementation engineer",
            "customer engineer",
            "integration engineer",
            "workflow engineer",
            "clinical software engineer",
            "digital health engineer",
            "healthcare ai engineer",
            "medtech engineer",
            "workflow automation engineer",
        ]

        let workflowTerms = [
            "workflow",
            "implementation",
            "integration",
            "customer deployment",
            "customer workflow",
            "provider workflow",
            "clinical workflow",
            "care navigation",
            "patient engagement",
            "interoperability",
            "ehr",
            "emr",
            "epic",
            "fhir",
            "hl7",
            "benefits",
            "remote patient monitoring",
            "wearable",
            "wearables",
        ]

        let healthcareTerms = [
            "healthcare",
            "health tech",
            "healthtech",
            "digital health",
            "medtech",
            "clinical",
            "medical device",
            "patient",
            "provider",
            "hipaa",
            "hospital",
            "care delivery",
        ]

        let mobileTerms = [
            "ios",
            "swift",
            "swiftui",
            "iphone",
            "ipad",
            "mobile",
            "app store",
        ]

        let aiProductTerms = [
            "applied ai",
            "ai product",
            "llm",
            "rag",
            "agent",
            "agentic",
            "generative ai",
            "automation",
            "developer tools",
            "mcp",
        ]

        let builderTerms = [
            "portfolio",
            "what you've built",
            "what you have built",
            "show us what you've built",
            "builder-first",
            "non-traditional",
            "shipped products",
            "ship fast",
            "rapid prototyping",
            "0-to-1",
            "zero-to-one",
            "founding",
            "first engineer",
        ]

        let strongTitleMatch = containsAny(strongTargetTitleTerms, in: title)
        let workflowHits = countMatches(workflowTerms, in: textBlob)
        let healthcareHits = countMatches(healthcareTerms, in: textBlob)
        let mobileHits = countMatches(mobileTerms, in: textBlob)
        let aiHits = countMatches(aiProductTerms, in: textBlob)
        let builderHits = countMatches(builderTerms, in: textBlob)
        let strongPositiveGroups = [workflowHits > 0, healthcareHits > 0, mobileHits > 0, aiHits > 0, builderHits > 0].filter { $0 }.count

        if strongTitleMatch {
            return true
        }

        if containsAny(hardRejectTitleTerms, in: title) {
            let escapeHatch = (healthcareHits > 0 && workflowHits > 0) || (healthcareHits > 0 && mobileHits > 0) || (aiHits > 0 && workflowHits > 0)
            return escapeHatch
        }

        if containsAny(["ios engineer", "ios developer", "swiftui engineer", "mobile engineer"], in: title) {
            return mobileHits > 0 && (healthcareHits > 0 || workflowHits > 0)
        }

        if containsAny(["product engineer", "prototype engineer", "founding engineer", "ai product engineer", "applied ai engineer", "ai product builder"], in: title) {
            return workflowHits > 0 || healthcareHits > 0 || (healthcareHits > 0 && aiHits > 0)
        }

        if title.contains("software engineer") {
            return (healthcareHits > 0 && workflowHits > 0) || (healthcareHits > 0 && mobileHits > 0) || (aiHits > 0 && workflowHits > 0)
        }

        return strongPositiveGroups >= 2 && (workflowHits > 0 || healthcareHits > 0)
    }

    /// Companies the user has blocked (loaded from @AppStorage via SettingsView)
    var blockedCompanies: Set<String> {
        guard let data = UserDefaults.standard.string(forKey: "blockedCompaniesJSON")?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(decoded.map { $0.lowercased() })
    }

    private var currentPreferences: UserPreferences {
        UserPreferences.currentFromUserDefaults()
    }

    private func matchesUserPendingPreferences(_ job: JobPayload, prefs: UserPreferences) -> Bool {
        if prefs.requireRemote && !job.isRemote {
            return false
        }

        let salaryCeiling = (job.salaryMax ?? 0) > 0 ? (job.salaryMax ?? 0) : job.salaryFloor
        if salaryCeiling > 0 && salaryCeiling < prefs.minSalary {
            return false
        }

        let searchableText = [
            job.roleTitle,
            job.companyName,
            job.location,
            job.description ?? "",
            job.companyDescription ?? "",
            job.logicFit ?? "",
            job.whyInteresting ?? "",
            job.jobSnapshot ?? "",
            (job.tags).joined(separator: " "),
            (job.techStack ?? []).joined(separator: " "),
        ]
        .joined(separator: " ")
        .lowercased()

        for keyword in prefs.excludedKeywords {
            let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty && searchableText.contains(normalized) {
                return false
            }
        }

        return true
    }

    /// Pending jobs with blocked companies and already-decided URLs filtered out, sorted by current mode
    var visiblePendingJobs: [JobPayload] {
        let blocked = blockedCompanies
        let decided = decidedURLs
        let prefs = currentPreferences

        let filtered = pendingJobs.filter { job in
            if !blocked.isEmpty && blocked.contains(job.companyName.lowercased()) { return false }
            if decided.contains(job.sourceUrl) { return false }
            if !matchesUserPendingPreferences(job, prefs: prefs) { return false }
            return true
        }

        return sortJobs(filtered)
    }

    /// Deterministic sort with tiebreakers — used by all views
    func sortJobs(_ jobs: [JobPayload]) -> [JobPayload] {
        jobs.sorted { a, b in
            switch sortMode {
            case .score:
                if a.effectiveBuilderScore != b.effectiveBuilderScore { return a.effectiveBuilderScore > b.effectiveBuilderScore }
                // Tiebreak: newer first, then alphabetical for full determinism
                let aDate = a.postedAt ?? .distantPast
                let bDate = b.postedAt ?? .distantPast
                if aDate != bDate { return aDate > bDate }
                return a.roleTitle < b.roleTitle

            case .newest:
                let aDate = a.postedAt ?? .distantPast
                let bDate = b.postedAt ?? .distantPast
                if aDate != bDate { return aDate > bDate }
                // Tiebreak: higher score first
                if a.effectiveBuilderScore != b.effectiveBuilderScore { return a.effectiveBuilderScore > b.effectiveBuilderScore }
                return a.roleTitle < b.roleTitle

            case .salary:
                if a.salaryFloor != b.salaryFloor { return a.salaryFloor > b.salaryFloor }
                // Tiebreak: higher score first
                if a.effectiveBuilderScore != b.effectiveBuilderScore { return a.effectiveBuilderScore > b.effectiveBuilderScore }
                return a.roleTitle < b.roleTitle
            }
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
        if l.circuitOpen {
            lines.append("│    circuit=OPEN \(l.circuitRemainingSeconds)s  reason=\(l.circuitReason)")
        } else if l.proCooldownActive {
            lines.append("│    gemini-pro-cooldown=\(l.proCooldownRemainingSeconds)s")
        }

        // Ingest
        let lockIcon = i.lockHeld ? "🔒" : "🔓"
        if p.phase == "idle" || p.phase == "complete" {
            let dur = p.lastDurationS.map { String(format: "%.1fs", $0) } ?? "-"
            lines.append("│ ⚙️ Ingest: \(p.phase)  \(lockIcon)  cycles=\(p.cyclesCompleted)  last=\(dur)")
        } else {
            lines.append("│ ⚙️ Ingest: \(p.phase.uppercased())  \(lockIcon)  batch \(p.batch)/\(p.totalBatches)")
            lines.append("│    fetched=\(p.fetched) new=\(p.newAfterDedup) scored=\(p.scored) queued=\(p.queued) rejected=\(p.rejected) low=\(p.lowScore) err=\(p.errors)")
            if let stage = p.currentStage,
               let item = p.currentItem,
               let total = p.currentTotal,
               let title = p.currentTitle,
               !title.isEmpty {
                let company = (p.currentCompany?.isEmpty == false) ? " @ \(p.currentCompany!)" : ""
                lines.append("│    \(stage.capitalized) \(item)/\(total): \(title)\(company)")
            }
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
        let cachedPending = Self.readCache("pending") ?? []
        let filteredPending = portfolioFirstGuardrail(cachedPending)
        pendingJobs = filteredPending.kept
        locallyFilteredPendingCount = filteredPending.dropped
        if filteredPending.dropped > 0 {
            Self.writeCache("pending", jobs: pendingJobs)
        }
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

    private static func clearCache(_ name: String) {
        let file = cacheDir.appendingPathComponent("\(name).json")
        try? FileManager.default.removeItem(at: file)
    }

    func resetLocalJobState() {
        fetchGeneration += 1
        print("[VM] resetLocalJobState — clearing in-memory + disk cache (gen=\(fetchGeneration))")
        pendingJobs = []
        savedJobs = []
        appliedJobs = []
        rejectedJobs = []
        stats = nil
        Self.clearCache("pending")
        Self.clearCache("saved")
        Self.clearCache("applied")
        Self.clearCache("rejected")
    }

    private func isExpectedCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private func isTransientBackendFailure(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            return apiError.isTransientServerFailure
        }
        if let urlError = error as? URLError {
            return [
                .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .networkConnectionLost,
                .dnsLookupFailed,
                .notConnectedToInternet,
                .resourceUnavailable,
            ].contains(urlError.code)
        }
        return false
    }

    private func applyFetchedPendingJobs(_ fetched: [JobPayload]) {
        let filteredPending = portfolioFirstGuardrail(fetched)
        pendingJobs = filteredPending.kept
        locallyFilteredPendingCount = filteredPending.dropped
        Self.writeCache("pending", jobs: pendingJobs)
        if filteredPending.dropped > 0 {
            self.info = "Locally filtered \(filteredPending.dropped) roles that missed your portfolio-first strategy"
        }
    }

    private func replacePendingJob(_ updated: JobPayload) {
        if let idx = pendingJobs.firstIndex(where: { $0.id == updated.id || $0.sourceUrl == updated.sourceUrl }) {
            pendingJobs[idx] = updated
            Self.writeCache("pending", jobs: pendingJobs)
        }
    }

    private func setHeuristicRecoveryBanner(_ message: String?, mode: HeuristicRecoveryMode?) {
        heuristicRecoveryBannerMessage = message
        heuristicRecoveryMode = mode
    }

    private func staleCloudQueueReason(for jobs: [JobPayload]) -> String? {
        guard BackendConfig.isCloud(url: currentServerURL), !jobs.isEmpty else {
            return nil
        }

        let datedJobs = jobs.compactMap(\ .postedAt)
        guard let newest = datedJobs.max() else {
            return nil
        }

        let ancientCutoff = Calendar.current.date(from: DateComponents(year: 2020, month: 1, day: 1)) ?? .distantPast
        if newest < ancientCutoff {
            return "newest job date is \(newest.formatted(date: .abbreviated, time: .omitted))"
        }

        let age = Date().timeIntervalSince(newest)
        if age > (21 * 24 * 60 * 60) {
            return "newest job is over 3 weeks old (\(newest.formatted(date: .abbreviated, time: .omitted)))"
        }

        return nil
    }

    private func recoverFromStaleCloudQueue(reason: String) async -> Bool {
        let current = currentServerURL
        print("[VM] stale cloud queue detected on \(current): \(reason)")

        if let alternative = await ServerDiscovery.discoverPreferredNonCloudAlternative(excluding: current),
           alternative != current {
            info = "Cloud queue looked stale — switched to \(BackendConfig.backendLabel(for: alternative)) and refreshing"
            resetLocalJobState()
            await loadPendingJobs()
            return true
        }

        info = "Cloud backend queue looks stale (\(reason)). Turn on Tailscale or switch servers in Settings."
        return false
    }

    private func maybeRecoverHeuristicPendingJobs() {
        let heuristicJobs = pendingJobs.filter { $0.scoringVersion == "local-v1" }
        guard !heuristicJobs.isEmpty else {
            setHeuristicRecoveryBanner(nil, mode: nil)
            return
        }
        guard !isRecoveringHeuristicJobs, !isRescoring, !isOffline else { return }
        guard Date().timeIntervalSince(lastHeuristicRecoveryAttempt) >= heuristicRecoveryCooldown else { return }

        lastHeuristicRecoveryAttempt = Date()
#if canImport(FoundationModels)
        let availability = OnDeviceJobScorer.availability
        if availability.isAvailable {
            Task {
                await recoverHeuristicPendingJobsOnDevice(heuristicJobs)
            }
            return
        }
#endif
        Task {
            await recoverHeuristicPendingJobsInBackend(expectedCount: heuristicJobs.count)
        }
    }

    private func recoverHeuristicPendingJobsOnDevice(_ jobs: [JobPayload]) async {
        guard !isRecoveringHeuristicJobs else { return }
        isRecoveringHeuristicJobs = true
        setHeuristicRecoveryBanner(
            "Recovering \(jobs.count) fallback jobs on-device with Apple Intelligence...",
            mode: .onDevice
        )

        var recovered = 0
        var persistFailures = 0
        let prefs = currentPreferences

        for (index, job) in jobs.enumerated() {
            setHeuristicRecoveryBanner(
                "Apple Intelligence rescoring \(index + 1)/\(jobs.count) fallback jobs...",
                mode: .onDevice
            )

            do {
#if canImport(FoundationModels)
                let rescored = try await OnDeviceJobScorer.rescore(job: job, preferences: prefs)
                replacePendingJob(rescored)
                do {
                    _ = try await APIClient.shared.importJobs([rescored], force: true)
                } catch {
                    persistFailures += 1
                    print("[VM] recoverHeuristicPendingJobsOnDevice — persist ERROR: \(error)")
                }
                recovered += 1
#endif
            } catch {
                print("[VM] recoverHeuristicPendingJobsOnDevice — scoring ERROR: \(error)")
            }
        }

        isRecoveringHeuristicJobs = false
        setHeuristicRecoveryBanner(nil, mode: nil)

        if recovered > 0 {
            do {
                let refreshed = try await APIClient.shared.fetchPendingJobs()
                applyFetchedPendingJobs(refreshed)
                await loadStats()
            } catch {
                print("[VM] recoverHeuristicPendingJobsOnDevice — refresh ERROR: \(error)")
            }
            info = "Recovered AI scoring on-device for \(recovered) jobs" + (persistFailures > 0 ? " (\(persistFailures) sync errors)" : "")
            return
        }

        await recoverHeuristicPendingJobsInBackend(expectedCount: jobs.count)
    }

    private func recoverHeuristicPendingJobsInBackend(expectedCount: Int) async {
        guard !isRecoveringHeuristicJobs else { return }
        isRecoveringHeuristicJobs = true
        setHeuristicRecoveryBanner(
            "Retrying \(expectedCount) fallback jobs with backend scorers...",
            mode: .cloud
        )

        do {
            let kickoff = try await APIClient.shared.rescoreJobs(
                buckets: ["pending"],
                heuristicOnly: true
            )
            let total = kickoff.total ?? 0
            if total == 0 {
                setHeuristicRecoveryBanner(nil, mode: nil)
                isRecoveringHeuristicJobs = false
                return
            }

            var pollCount = 0
            let maxPolls = 180
            while pollCount < maxPolls {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                pollCount += 1

                let status = try await APIClient.shared.fetchRescoreStatus()
                if status.running == true {
                    let done = status.done ?? 0
                    let statusTotal = status.total ?? total
                    setHeuristicRecoveryBanner(
                        "Retrying fallback jobs with backend scorers... \(done)/\(statusTotal)",
                        mode: .cloud
                    )
                    continue
                }

                let refreshed = try await APIClient.shared.fetchPendingJobs()
                applyFetchedPendingJobs(refreshed)
                await loadStats()

                let done = status.done ?? total
                let errors = status.errors ?? 0
                isRecoveringHeuristicJobs = false
                setHeuristicRecoveryBanner(nil, mode: nil)
                info = "Recovered AI scoring for \(done) jobs" + (errors > 0 ? " (\(errors) errors)" : "")
                return
            }

            let refreshed = try await APIClient.shared.fetchPendingJobs()
            applyFetchedPendingJobs(refreshed)
            await loadStats()
            isRecoveringHeuristicJobs = false
            setHeuristicRecoveryBanner(nil, mode: nil)
            info = "AI recovery still running — refreshed current queue"
        } catch {
            isRecoveringHeuristicJobs = false
            setHeuristicRecoveryBanner(nil, mode: nil)
            print("[VM] recoverHeuristicPendingJobsInBackend — ERROR: \(error)")
        }
    }

    func loadPendingJobs() async {
        isLoading = true
        defer { isLoading = false }
        let gen = fetchGeneration
        let server = currentServerURL
        print("[VM] loadPendingJobs — starting (gen=\(gen), server=\(server))")

        do {
            let fetched = try await APIClient.shared.fetchPendingJobs()

            // If the server changed while we were fetching, discard stale results
            guard fetchGeneration == gen else {
                print("[VM] loadPendingJobs — DISCARDED stale results (gen \(gen) != current \(fetchGeneration)) — server changed mid-fetch")
                return
            }

            isOffline = false
            error = nil

            if let staleReason = staleCloudQueueReason(for: fetched) {
                let switched = await recoverFromStaleCloudQueue(reason: staleReason)
                if switched || fetchGeneration != gen {
                    return
                }
            }

            applyFetchedPendingJobs(fetched)
            print("[VM] loadPendingJobs — got \(pendingJobs.count) jobs")
            for (i, j) in pendingJobs.prefix(5).enumerated() {
                print("[VM]   [\(i)] \(j.roleTitle) @ \(j.companyName) score=\(j.builderScore)")
            }
            maybeRecoverHeuristicPendingJobs()
        } catch {
            if isExpectedCancellation(error) {
                print("[VM] loadPendingJobs — cancelled (superseded)")
                return
            }
            // Also discard errors from stale fetches
            guard fetchGeneration == gen else {
                print("[VM] loadPendingJobs — ignoring error from stale fetch (gen \(gen))")
                return
            }
            print("[VM] loadPendingJobs — ERROR: \(error)")
            isOffline = true
            if pendingJobs.isEmpty {
                self.error = "Can't reach \(currentBackendLabel) — check that your Mac is awake, Docker is running, or switch servers in Settings"
            } else {
                self.info = "Offline — showing \(pendingJobs.count) cached jobs from \(currentBackendLabel)"
            }
        }
    }

    func loadAppliedJobs() async {
        let gen = fetchGeneration
        print("[VM] loadAppliedJobs — starting")
        do {
            let fetched = try await APIClient.shared.fetchAppliedJobs()
            guard fetchGeneration == gen else {
                print("[VM] loadAppliedJobs — DISCARDED stale results (gen \(gen))")
                return
            }
            appliedJobs = fetched
            Self.writeCache("applied", jobs: appliedJobs)
            print("[VM] loadAppliedJobs — got \(appliedJobs.count)")
        } catch {
            if isExpectedCancellation(error) {
                print("[VM] loadAppliedJobs — cancelled (superseded)")
                return
            }
            print("[VM] loadAppliedJobs — ERROR (suppressed): \(error)")
        }
    }

    func loadSavedJobs() async {
        let gen = fetchGeneration
        print("[VM] loadSavedJobs — starting")
        do {
            let fetched = try await APIClient.shared.fetchSavedJobs()
            guard fetchGeneration == gen else {
                print("[VM] loadSavedJobs — DISCARDED stale results (gen \(gen))")
                return
            }
            savedJobs = fetched
            Self.writeCache("saved", jobs: savedJobs)
            print("[VM] loadSavedJobs — got \(savedJobs.count)")
        } catch {
            if isExpectedCancellation(error) {
                print("[VM] loadSavedJobs — cancelled (superseded)")
                return
            }
            print("[VM] loadSavedJobs — ERROR (suppressed): \(error)")
        }
    }

    func loadRejectedJobs() async {
        print("[VM] loadRejectedJobs — starting")
        do {
            let fetched = try await APIClient.shared.fetchRejectedJobs()
            rejectedJobs = fetched
            Self.writeCache("rejected", jobs: rejectedJobs)
            print("[VM] loadRejectedJobs — got \(rejectedJobs.count)")
        } catch {
            if isExpectedCancellation(error) {
                print("[VM] loadRejectedJobs — cancelled (superseded)")
                return
            }
            print("[VM] loadRejectedJobs — ERROR (suppressed): \(error)")
        }
    }

    func loadStats() async {
        statsLoading = true
        defer { statsLoading = false }
        let gen = fetchGeneration
        print("[VM] loadStats — starting")
        do {
            let fetched = try await APIClient.shared.fetchStats()
            guard fetchGeneration == gen else {
                print("[VM] loadStats — DISCARDED stale results (gen \(gen))")
                return
            }
            stats = fetched
            if let s = stats {
                print("[VM] loadStats — pending=\(s.pending) applied=\(s.applied) saved=\(s.saved) rejected=\(s.rejected)")
            }
        } catch {
            if isExpectedCancellation(error) {
                print("[VM] loadStats — cancelled (superseded)")
                return
            }
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
        async let p: () = loadPendingJobs()
        async let a: () = loadAppliedJobs()
        async let s: () = loadSavedJobs()
        async let st: () = loadStats()
        _ = await (p, a, s, st)
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

            let startingPendingCount = pendingJobs.count
            var lastObservedPendingCount = pendingJobs.count

            // Poll for completion — use cycle_active to detect ongoing periodic ingest too
            ingestProgress = "Scanning & scoring with AI..."
            var pollCount = 0
            let maxPolls = 300  // ~10 minutes max (ingest can take 5-10 min)
            while pollCount < maxPolls {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                pollCount += 1

                let status: IngestStatusResponse
                do {
                    status = try await APIClient.shared.fetchIngestStatus()
                } catch {
                    if isExpectedCancellation(error) {
                        print("[VM] ingestNewJobs — polling cancelled")
                        return
                    }
                    if isTransientBackendFailure(error) {
                        print("[VM] ingestNewJobs — transient ingest-status failure: \(error.localizedDescription)")
                        ingestProgress = "Backend waking up… retrying status check"
                        continue
                    }
                    throw error
                }
                let stillActive = status.manualRunning || (status.cycleActive ?? false)

                if status.store.pending > lastObservedPendingCount {
                    print("[VM] ingestNewJobs — pending grew \(lastObservedPendingCount) → \(status.store.pending), live-refreshing queue")
                    do {
                        let fetchedPending = try await APIClient.shared.fetchPendingJobs()
                        applyFetchedPendingJobs(fetchedPending)
                        stats = status.store
                        lastObservedPendingCount = pendingJobs.count
                        let newCount = max(pendingJobs.count - startingPendingCount, 0)
                        print("[VM] ingestNewJobs — live queue now has \(pendingJobs.count) jobs (\(newCount) new this run)")
                    } catch {
                        if isTransientBackendFailure(error) {
                            print("[VM] ingestNewJobs — transient pending refresh failure: \(error.localizedDescription)")
                        } else {
                            throw error
                        }
                    }
                }

                // Pull live telemetry during ingest for console visibility
                if pollCount % 3 == 0 { // Every ~6s
                    await fetchAndLogTelemetry()
                }

                if !stillActive {
                    // Ingest finished
                    let ingested = status.lastIngestResult ?? 0
                    print("[VM] ingestNewJobs — done after \(pollCount) polls, ingested=\(ingested)")
                    ingestProgress = "Loading results..."
                    do {
                        let refreshed = try await APIClient.shared.fetchPendingJobs()
                        applyFetchedPendingJobs(refreshed)
                    } catch {
                        if isTransientBackendFailure(error) {
                            print("[VM] ingestNewJobs — transient final pending fetch failure: \(error.localizedDescription)")
                        } else {
                            throw error
                        }
                    }
                    print("[VM] ingestNewJobs — pending queue now has \(pendingJobs.count) jobs")
                    await loadStats()

                    // Even if this manual ingest scored 0, the periodic ingest may have
                    // queued jobs while we were waiting for the lock.
                    if pendingJobs.isEmpty && status.store.pending > 0 {
                        print("[VM] ingestNewJobs — store has \(status.store.pending) but fetch returned 0, retrying...")
                        let refreshed = try await APIClient.shared.fetchPendingJobs()
                        applyFetchedPendingJobs(refreshed)
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
                        let detail: String
                        if let stage = p.currentStage,
                           let item = p.currentItem,
                           let total = p.currentTotal,
                           let title = p.currentTitle,
                           !title.isEmpty {
                            detail = "\(stage.capitalized) \(item)/\(total): \(title)"
                        } else {
                            detail = "Scoring batch \(p.batch)/\(p.totalBatches)"
                        }
                        let liveAdded = max(status.store.pending - startingPendingCount, 0)
                        ingestProgress = "\(detail) — \(p.queued) queued so far, \(liveAdded) live"
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
            let refreshed = try await APIClient.shared.fetchPendingJobs()
            applyFetchedPendingJobs(refreshed)
            await loadStats()
            info = "Scoring is still running — pull to refresh for latest results"

        } catch {
            if isTransientBackendFailure(error) {
                print("[VM] ingestNewJobs — transient top-level failure: \(error.localizedDescription)")
                info = "Backend had a temporary hiccup. Pull to refresh in a few seconds."
                return
            }
            print("[VM] ingestNewJobs — ERROR: \(error)")
            self.error = error.localizedDescription
        }
    }

    /// Auto-ingest once per session when the queue loads empty
    func autoIngestIfNeeded() async {
        let visible = visiblePendingJobs.count
        let statsPending = stats?.pending ?? 0
        print("[VM] autoIngestIfNeeded — pending=\(pendingJobs.count) visible=\(visible) statsPending=\(statsPending) ingesting=\(isIngesting) loading=\(isLoading) offline=\(isOffline) alreadyDone=\(hasAutoIngested) errorPresent=\(error != nil)")
        guard visible == 0,
              pendingJobs.isEmpty,
              statsPending == 0,
              !isIngesting,
              !isLoading,
              !isOffline,
              error == nil,
              !hasAutoIngested else {
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
                    let refreshed = try await APIClient.shared.fetchPendingJobs()
                    applyFetchedPendingJobs(refreshed)
                    await loadStats()
                    info = "Rescored \(done) jobs" + (errors > 0 ? " (\(errors) errors)" : "")
                    return
                }
            }

            // Timed out
            print("[VM] rescoreAllJobs — polling timed out")
            let refreshed = try await APIClient.shared.fetchPendingJobs()
            applyFetchedPendingJobs(refreshed)
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

    // MARK: - LinkedIn Social Actions

    func fetchOwnPosts(personId: String) async {
        isSocialLoading = true
        socialError = nil
        do {
                self.linkedInPosts = try await APIClient.shared.fetchLinkedInPostsParsed(personId: personId)
        } catch {
            socialError = error.localizedDescription
            print("Failed to fetch LinkedIn posts: \(error)")
        }
        isSocialLoading = false
    }

    func deletePost(personId: String, postUrn: String) async {
        do {
            _ = try await APIClient.shared.deleteLinkedInPost(personId: personId, postUrn: postUrn)
            self.linkedInPosts.removeAll { $0.urn == postUrn }
        } catch {
            socialError = error.localizedDescription
            print("Failed to delete post: \(error)")
        }
    }

    func fetchComments(personId: String, postUrn: String) async {
        do {
            self.linkedInComments[postUrn] = try await APIClient.shared.fetchLinkedInCommentsParsed(personId: personId, postUrn: postUrn)
        } catch {
            socialError = error.localizedDescription
            print("Failed to fetch comments for \(postUrn): \(error)")
        }
    }

    func addComment(personId: String, postUrn: String, text: String) async {
        do {
            _ = try await APIClient.shared.addLinkedInComment(personId: personId, postUrn: postUrn, text: text)
            // Re-fetch comments to update the list
            await fetchComments(personId: personId, postUrn: postUrn)
        } catch {
            socialError = error.localizedDescription
            print("Failed to add comment: \(error)")
        }
    }

    func deleteComment(personId: String, postUrn: String, commentId: String) async {
        do {
            _ = try await APIClient.shared.deleteLinkedInComment(personId: personId, postUrn: postUrn, commentId: commentId)
            self.linkedInComments[postUrn]?.removeAll { $0.urn == commentId }
        } catch {
            socialError = error.localizedDescription
            print("Failed to delete comment: \(error)")
        }
    }

    func fetchReactions(personId: String, postUrn: String) async {
        do {
            self.linkedInReactions[postUrn] = try await APIClient.shared.fetchLinkedInReactionsParsed(personId: personId, postUrn: postUrn)
        } catch {
            socialError = error.localizedDescription
            print("Failed to fetch reactions for \(postUrn): \(error)")
        }
    }

    func toggleReaction(personId: String, postUrn: String, isAdding: Bool) async {
        do {
            if isAdding {
                _ = try await APIClient.shared.addLinkedInReaction(personId: personId, postUrn: postUrn, reaction: "LIKE")
            } else {
                _ = try await APIClient.shared.removeLinkedInReaction(personId: personId, postUrn: postUrn)
            }
            // Re-fetch to update state accurately
            await fetchReactions(personId: personId, postUrn: postUrn)
        } catch {
            socialError = error.localizedDescription
            print("Failed to toggle reaction: \(error)")
        }
    }
}
