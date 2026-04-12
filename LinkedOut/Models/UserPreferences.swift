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
    var preferredLocations: [String]

    // ── Scoring Weights (adjustable) ──
    var scoreCutoff: Double
    var convincingPenalty: Double       // negative, e.g. -0.20
    var convincingBoost: Double         // positive, e.g.  0.10
    var nearbyPenalty: Double           // negative, e.g. -0.03
    var nearbyPenaltyMult: Double       // multiplier, e.g. 0.97
    var regionalPenalty: Double         // negative, e.g. -0.08
    var regionalPenaltyMult: Double     // multiplier, e.g. 0.92
    var relocationPenalty: Double       // negative, e.g. -0.15
    var relocationPenaltyMult: Double   // multiplier, e.g. 0.85
    var internationalPenalty: Double    // negative, e.g. -0.25
    var internationalPenaltyMult: Double // multiplier, e.g. 0.75
    var experiencePenalty: Double       // negative, e.g. -0.10
    var credentialPenalty: Double       // negative, e.g. -0.15
    var portfolioBoost: Double          // positive, e.g.  0.10
    var maxSeniorityLevel: String       // "Mid", "Senior", "Any"
    var professionalProfile: String     // AI resume chunk

    enum CodingKeys: String, CodingKey {
        case minSalary = "min_salary"
        case requireRemote = "require_remote"
        case preferredRoles = "preferred_roles"
        case excludedKeywords = "excluded_keywords"
        case locationPreference = "location_preference"
        case preferredLocations = "preferred_locations"
        case scoreCutoff = "score_cutoff"
        case convincingPenalty = "convincing_penalty"
        case convincingBoost = "convincing_boost"
        case nearbyPenalty = "nearby_penalty"
        case nearbyPenaltyMult = "nearby_penalty_mult"
        case regionalPenalty = "regional_penalty"
        case regionalPenaltyMult = "regional_penalty_mult"
        case relocationPenalty = "relocation_penalty"
        case relocationPenaltyMult = "relocation_penalty_mult"
        case internationalPenalty = "international_penalty"
        case internationalPenaltyMult = "international_penalty_mult"
        case experiencePenalty = "experience_penalty"
        case credentialPenalty = "credential_penalty"
        case portfolioBoost = "portfolio_boost"
        case maxSeniorityLevel = "max_seniority_level"
        case professionalProfile = "professional_profile"
    }

    static let `default` = UserPreferences(
        minSalary: 90000,
        requireRemote: true,
        preferredRoles: [
            "AI Engineer",
            "AI Product Engineer",
            "AI Product Builder",
            "Applied AI Engineer",
            "AI Prototyper",
            "Founding Engineer",
            "Product Engineer",
            "Prototype Engineer",
            "Product Development Generalist",
            "iOS Engineer",
            "Mobile Engineer",
            "Machine Learning Engineer",
            "Software Engineer",
            "Full Stack Engineer",
            "Developer Experience Engineer"
        ],
        excludedKeywords: [
            "Staff Engineer",
            "Principal Engineer",
            "Engineering Manager",
            "Director of Engineering",
            "LeetCode",
            "whiteboard",
            "competitive programming",
            "10+ years",
            "DevOps",
            "SRE"
        ],
        locationPreference: "Remote",
        preferredLocations: ["Campbell, California", "Palo Alto, California"],
        scoreCutoff: 0.30,
        convincingPenalty: -0.20,
        convincingBoost: 0.10,
        nearbyPenalty: -0.03,
        nearbyPenaltyMult: 0.97,
        regionalPenalty: -0.08,
        regionalPenaltyMult: 0.92,
        relocationPenalty: -0.15,
        relocationPenaltyMult: 0.85,
        internationalPenalty: -0.25,
        internationalPenaltyMult: 0.75,
        experiencePenalty: -0.10,
        credentialPenalty: -0.15,
        portfolioBoost: 0.10,
        maxSeniorityLevel: "Mid",
        professionalProfile: "AI-native builder with 4 App Store apps, SwiftUI plus Python backends, healthcare ops depth from Stryker / VA Palo Alto, and real product proof including early paid OpenIntelligence cohort sales."
    )
}
