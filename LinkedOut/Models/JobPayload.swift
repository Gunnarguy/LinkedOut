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
    var logicFit: String?
    var domainLeverage: String?
    var riskReward: String?

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
        Int(builderScore * 100)
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

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case action
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
