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
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: JobPayload, rhs: JobPayload) -> Bool {
        lhs.id == rhs.id
    }

    /// Formatted salary string
    var salaryDisplay: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: salaryFloor)) ?? "$\(salaryFloor)")+"
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
