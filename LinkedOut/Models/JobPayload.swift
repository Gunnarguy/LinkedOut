//
//  JobPayload.swift
//  LinkedOut
//
//  The immutable data contract — mirrors the Python Pydantic model exactly.
//

import Foundation

struct JobPayload: Codable, Identifiable, Hashable {
    let id: String
    let companyName: String
    let roleTitle: String
    let salaryFloor: Int
    let isRemote: Bool
    let builderScore: Double
    let aiPitchSummary: String
    let draftedCoverLetter: String
    let sourceUrl: String
    let postedAt: Date?
    let location: String
    let tags: [String]

    // Rich company intelligence (all optional for backward compat)
    var description: String?
    var companyDescription: String?
    var companySize: String?
    var companyStage: String?
    var companyUrl: String?
    var salaryMax: Int?
    var requirements: [String]?
    var niceToHaves: [String]?
    var techStack: [String]?
    var whyInteresting: String?
    var redFlags: [String]?
    var applyUrl: String?
    var experienceLevel: String?
    var jobType: String?
    var benefits: [String]?
    var fitReasons: [String]?
    var dealbreakerWarnings: [String]?

    // Why Matrix (structured factual assessment)
    var jobSnapshot: String?
    var companyOneliner: String?
    var theyWant: [String]?
    var logicFit: String?
    var domainLeverage: String?
    var riskReward: String?

    // Structured scoring factors (v2)
    var domainAlignment: Double?
    var roleAlignment: Double?
    var cultureFit: Double?
    var experienceFriction: Double?
    var stackFit: Double?
    var caveats: [String]?
    var scoringVersion: String?

    // User-managed fields
    var notes: String?
    var applicationStatus: String?

    // Notion sync
    var notionPageId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyName = "company_name"
        case roleTitle = "role_title"
        case salaryFloor = "salary_floor"
        case isRemote = "is_remote"
        case builderScore = "builder_score"
        case aiPitchSummary = "ai_pitch_summary"
        case draftedCoverLetter = "drafted_cover_letter"
        case sourceUrl = "source_url"
        case postedAt = "posted_at"
        case location
        case tags
        case description
        case companyDescription = "company_description"
        case companySize = "company_size"
        case companyStage = "company_stage"
        case companyUrl = "company_url"
        case salaryMax = "salary_max"
        case requirements
        case niceToHaves = "nice_to_haves"
        case techStack = "tech_stack"
        case whyInteresting = "why_interesting"
        case jobSnapshot = "job_snapshot"
        case companyOneliner = "company_oneliner"
        case theyWant = "they_want"
        case redFlags = "red_flags"
        case applyUrl = "apply_url"
        case experienceLevel = "experience_level"
        case jobType = "job_type"
        case benefits
        case fitReasons = "fit_reasons"
        case dealbreakerWarnings = "dealbreaker_warnings"
        case logicFit = "logic_fit"
        case domainLeverage = "domain_leverage"
        case riskReward = "risk_reward"
        case domainAlignment = "domain_alignment"
        case roleAlignment = "role_alignment"
        case cultureFit = "culture_fit"
        case experienceFriction = "experience_friction"
        case stackFit = "stack_fit"
        case caveats
        case scoringVersion = "scoring_version"
        case notes
        case applicationStatus = "application_status"
        case notionPageId = "notion_page_id"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: JobPayload, rhs: JobPayload) -> Bool {
        lhs.id == rhs.id
    }

    private static func normalizedAssessmentText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        if normalized.contains("generic full-stack or backend software role")
            && normalized.contains("target lanes") {
            return "Listing leans toward a general full-stack or backend seat and looks less tied to your strongest product, workflow, mobile, or healthcare angles."
        }

        if normalized.contains("generic full-stack or backend work")
            && normalized.contains("builder lanes") {
            return "Role reads more like a general full-stack or backend seat than one built around your strongest product, workflow, mobile, or healthcare angles."
        }

        if normalized.contains("specialist ml or security role")
            && normalized.contains("product-builder lane") {
            return "Role leans toward specialized ML or security work and looks less aligned with your strongest product, workflow, mobile, or healthcare angles."
        }

        if normalized.contains("specialized ml or security work")
            && normalized.contains("lane you're actually targeting") {
            return "Role leans toward specialized ML or security work and looks less aligned with your strongest product, workflow, mobile, or healthcare angles."
        }

        return trimmed
    }

    static func normalizedBuilderScore(
        rawScore: Double,
        scoringVersion: String?,
        domainAlignment: Double?,
        roleAlignment: Double?,
        cultureFit: Double?,
        experienceFriction: Double?,
        stackFit: Double?
    ) -> Double {
        var adjusted = min(max(rawScore, 0.0), 1.0)

        let factors = [
            (domainAlignment ?? 0.0, 0.20),
            (roleAlignment ?? 0.0, 0.30),
            (cultureFit ?? 0.0, 0.20),
            (experienceFriction ?? 0.0, 0.15),
            (stackFit ?? 0.0, 0.15),
        ]
        let weightedComposite = factors.reduce(0.0) { partial, item in
            partial + (item.0 * item.1)
        }

        if scoringVersion == "apple-intelligence-v1", weightedComposite > 0 {
            adjusted = min(adjusted, min(1.0, weightedComposite + 0.05))
        }

        if let roleAlignment {
            if roleAlignment < 0.25 {
                adjusted = min(adjusted, 0.35)
            } else if roleAlignment < 0.35 {
                adjusted = min(adjusted, 0.45)
            } else if roleAlignment < 0.45 {
                adjusted = min(adjusted, 0.60)
            }
        }

        return (adjusted * 100).rounded() / 100
    }

    var effectiveBuilderScore: Double {
        Self.normalizedBuilderScore(
            rawScore: builderScore,
            scoringVersion: scoringVersion,
            domainAlignment: domainAlignment,
            roleAlignment: roleAlignment,
            cultureFit: cultureFit,
            experienceFriction: experienceFriction,
            stackFit: stackFit
        )
    }

    var displayDealbreakerWarnings: [String] {
        (dealbreakerWarnings ?? [])
            .map(Self.normalizedAssessmentText)
            .filter { !$0.isEmpty }
    }

    var displayCaveats: [String] {
        (caveats ?? [])
            .map(Self.normalizedAssessmentText)
            .filter { !$0.isEmpty }
    }

    /// Formatted salary string (range if max available)
    var salaryDisplay: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        let floor = formatter.string(from: NSNumber(value: salaryFloor)) ?? "$\(salaryFloor)"
        if let max = salaryMax, max > salaryFloor {
            let maxStr = formatter.string(from: NSNumber(value: max)) ?? "$\(max)"
            return "\(floor) – \(maxStr)"
        }
        return salaryFloor > 0 ? "\(floor)+" : "Not listed"
    }

    /// Score as percentage (0–100)
    var scorePercent: Int {
        Int(effectiveBuilderScore * 100)
    }

    /// Pitch bullets as array
    var pitchBullets: [String] {
        aiPitchSummary
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Formatted application status
    var statusDisplay: String {
        switch applicationStatus ?? "new" {
        case "new": return "New"
        case "applied": return "Applied"
        case "phone_screen": return "Phone Screen"
        case "interview": return "Interview"
        case "offer": return "Offer"
        case "rejected": return "Rejected"
        default: return applicationStatus ?? "New"
        }
    }

    /// Has any rich company intel?
    var hasCompanyIntel: Bool {
        (companyDescription ?? "").count > 5 ||
        (companyStage ?? "").count > 1 ||
        !(techStack ?? []).isEmpty
    }

    /// Which job board this came from, derived from sourceUrl
    var sourceName: String {
        let url = sourceUrl.lowercased()
        if url.contains("remotive.com") { return "Remotive" }
        if url.contains("himalayas.app") { return "Himalayas" }
        if url.contains("jobicy.com") { return "Jobicy" }
        if url.contains("remoteok.com") { return "RemoteOK" }
        if url.contains("weworkremotely.com") { return "WWR" }
        if url.contains("arbeitnow.com") { return "Arbeitnow" }
        if url.contains("themuse.com") { return "The Muse" }
        if url.contains("news.ycombinator.com") || url.contains("hacker-news") { return "HN" }
        if url.contains("lever.co") { return "Lever" }
        if url.contains("greenhouse.io") { return "Greenhouse" }
        if url.contains("ashbyhq.com") { return "Ashby" }
        return "Direct"
    }

    // MARK: - Date Helpers

    /// Relative freshness label — "Just now", "2h ago", "3d ago", etc.
    var freshnessLabel: String {
        guard let date = postedAt else { return "Unknown" }
        let seconds = -date.timeIntervalSinceNow
        switch seconds {
        case ..<60:          return "Just now"
        case ..<3600:        return "\(Int(seconds / 60))m ago"
        case ..<86400:       return "\(Int(seconds / 3600))h ago"
        case ..<604800:      return "\(Int(seconds / 86400))d ago"
        default:             return "\(Int(seconds / 604800))w ago"
        }
    }

    /// Short formatted posting date — "Mar 13" or "Dec 5, 2025"
    var postedDateDisplay: String {
        guard let date = postedAt else { return "—" }
        let cal = Calendar.current
        let fmt = DateFormatter()
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            fmt.dateFormat = "MMM d"
        } else {
            fmt.dateFormat = "MMM d, yyyy"
        }
        return fmt.string(from: date)
    }

    /// Shareable text for this job
    var shareText: String {
        var parts = ["\(roleTitle) at \(companyName)"]
        if salaryFloor > 0 { parts.append(salaryDisplay) }
        if isRemote { parts.append("Remote") }
        parts.append(applyUrl ?? sourceUrl)
        return parts.joined(separator: " \u{2022} ")
    }

    /// How many requirements the user likely matches (based on fit reasons count vs requirements)
    var requirementsMatchLabel: String? {
        guard let reqs = requirements, !reqs.isEmpty else { return nil }
        let fitCount = fitReasons?.count ?? 0
        // Rough heuristic: fit reasons map ~1:1 to matched requirements
        let matched = min(fitCount, reqs.count)
        return "\(matched)/\(reqs.count)"
    }
}

// MARK: - Action Models

enum JobAction: String, Codable {
    case apply
    case reject
    case save
}

struct JobActionRequest: Codable {
    let jobId: String
    let action: JobAction
    let jobData: JobPayload?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case action
        case jobData = "job_data"
    }
}

struct JobActionResponse: Codable {
    let jobId: String
    let action: JobAction
    let success: Bool
    let message: String

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case action, success, message
    }
}

struct JobNotesUpdate: Codable {
    let notes: String
}

struct JobStatusUpdate: Codable {
    let status: String
}

struct UndoResponse: Codable {
    let success: Bool
    let jobId: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case jobId = "job_id"
        case message
    }
}
