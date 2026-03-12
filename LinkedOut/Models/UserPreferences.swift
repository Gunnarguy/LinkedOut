//
//  UserPreferences.swift
//  LinkedOut
//
//  User's job search preferences — synced with backend.
//

import Foundation

struct UserPreferences: Codable {
    var minSalary: Int
    var requireRemote: Bool
    var preferredRoles: [String]
    var excludedKeywords: [String]
    var locationPreference: String

    // ── Scoring Weights (adjustable) ──
    var scoreCutoff: Double
    var convincingPenalty: Double       // negative, e.g. -0.20
    var convincingBoost: Double         // positive, e.g.  0.10
    var relocationPenalty: Double       // negative, e.g. -0.15
    var internationalPenalty: Double    // negative, e.g. -0.25
    var experiencePenalty: Double       // negative, e.g. -0.10
    var credentialPenalty: Double       // negative, e.g. -0.15
    var portfolioBoost: Double          // positive, e.g.  0.10
    var maxSeniorityLevel: String       // "Mid", "Senior", "Any"

    enum CodingKeys: String, CodingKey {
        case minSalary = "min_salary"
        case requireRemote = "require_remote"
        case preferredRoles = "preferred_roles"
        case excludedKeywords = "excluded_keywords"
        case locationPreference = "location_preference"
        case scoreCutoff = "score_cutoff"
        case convincingPenalty = "convincing_penalty"
        case convincingBoost = "convincing_boost"
        case relocationPenalty = "relocation_penalty"
        case internationalPenalty = "international_penalty"
        case experiencePenalty = "experience_penalty"
        case credentialPenalty = "credential_penalty"
        case portfolioBoost = "portfolio_boost"
        case maxSeniorityLevel = "max_seniority_level"
    }

    static let `default` = UserPreferences(
        minSalary: 90000,
        requireRemote: true,
        preferredRoles: [
            "AI Product Engineer",
            "AI Engineer",
            "Founding Engineer",
            "Product Engineer",
            "iOS Engineer",
            "Machine Learning Engineer"
        ],
        excludedKeywords: [
            "LeetCode",
            "whiteboard",
            "competitive programming",
            "10+ years",
            "Staff Engineer",
            "Principal Engineer",
            "DevOps",
            "SRE"
        ],
        locationPreference: "Remote",
        scoreCutoff: 0.35,
        convincingPenalty: -0.20,
        convincingBoost: 0.10,
        relocationPenalty: -0.15,
        internationalPenalty: -0.25,
        experiencePenalty: -0.10,
        credentialPenalty: -0.15,
        portfolioBoost: 0.10,
        maxSeniorityLevel: "Mid"
    )
}
