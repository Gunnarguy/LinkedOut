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
        minSalary: 70000,
        requireRemote: true,
        preferredRoles: [
            "Forward Deployed Engineer",
            "Forward-Deployed Engineer",
            "Solutions Engineer",
            "Technical Solutions Engineer",
            "Clinical Solutions Engineer",
            "Implementation Engineer",
            "Technical Implementation Engineer",
            "Customer Engineer",
            "Integration Engineer",
            "Workflow Engineer",
            "AI Product Engineer",
            "AI Product Builder",
            "Applied AI Engineer",
            "AI Prototyper",
            "Founding Engineer",
            "Product Engineer",
            "Prototype Engineer",
            "iOS Engineer",
            "iOS Developer",
            "SwiftUI Engineer",
            "Mobile Engineer",
            "Clinical Software Engineer",
            "Digital Health Engineer",
            "Healthcare AI Engineer",
            "MedTech Engineer",
            "Workflow Automation Engineer"
        ],
        excludedKeywords: [
            "Senior Engineer",
            "Senior Software Engineer",
            "Senior Backend Engineer",
            "Senior Platform Engineer",
            "Sr. Engineer",
            "Staff Engineer",
            "Principal Engineer",
            "Lead Engineer",
            "Lead Software Engineer",
            "Engineering Manager",
            "Director of Engineering",
            "Head of Engineering",
            "Architect",
            "LeetCode",
            "whiteboard",
            "competitive programming",
            "6+ years",
            "7+ years",
            "8+ years",
            "9+ years",
            "10+ years",
            "11+ years",
            "12+ years",
            "DevOps",
            "SRE",
            "Platform Engineer",
            "Infrastructure Engineer",
            "Site Reliability Engineer",
            "Full-Stack Engineer",
            "Full Stack Engineer",
            "Full-Stack Software Engineer",
            "Full-Stack Developer",
            "Backend Engineer",
            "Backend Developer",
            "Machine Learning Engineer",
            "ML Engineer",
            "Cyber Security",
            "Cybersecurity",
            "Security Engineer",
            "Sales Engineer"
        ],
        locationPreference: "Remote",
        preferredLocations: ["Campbell, California", "Palo Alto, California"],
        scoreCutoff: 0.58,
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
        professionalProfile: """
    ### Target: High-Agency Product and Workflow Builder

    Treat this candidate as a high-agency, AI-enabled product and workflow builder with real healthcare context, not as a conventional generic software engineer.

    Higher-confidence directions:
    - iOS or mobile product work
    - Healthcare, digital health, clinical software, or medtech
    - Forward-deployed, solutions, implementation, integration, or workflow roles that are genuinely technical
    - Applied-AI product builder or prototype roles where shipping and problem-solving matter more than pedigree
    """
    )

    static func currentFromUserDefaults(_ defaults: UserDefaults = .standard) -> UserPreferences {
        func stringArray(forKey key: String, fallback: [String]) -> [String] {
            guard let raw = defaults.string(forKey: key)?.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: raw) else {
                return fallback
            }
            return decoded
        }

        return UserPreferences(
            minSalary: defaults.object(forKey: "minSalary") as? Int ?? UserPreferences.default.minSalary,
            requireRemote: defaults.object(forKey: "requireRemote") as? Bool ?? UserPreferences.default.requireRemote,
            preferredRoles: stringArray(forKey: "preferredRolesJSON", fallback: UserPreferences.default.preferredRoles),
            excludedKeywords: stringArray(forKey: "excludedKeywordsJSON", fallback: UserPreferences.default.excludedKeywords),
            locationPreference: defaults.string(forKey: "locationPreference") ?? UserPreferences.default.locationPreference,
            preferredLocations: stringArray(forKey: "preferredLocationsJSON", fallback: UserPreferences.default.preferredLocations),
            scoreCutoff: defaults.object(forKey: "scoreCutoff") as? Double ?? UserPreferences.default.scoreCutoff,
            convincingPenalty: defaults.object(forKey: "convincingPenalty") as? Double ?? UserPreferences.default.convincingPenalty,
            convincingBoost: defaults.object(forKey: "convincingBoost") as? Double ?? UserPreferences.default.convincingBoost,
            nearbyPenalty: defaults.object(forKey: "nearbyPenalty") as? Double ?? UserPreferences.default.nearbyPenalty,
            nearbyPenaltyMult: defaults.object(forKey: "nearbyPenaltyMult") as? Double ?? UserPreferences.default.nearbyPenaltyMult,
            regionalPenalty: defaults.object(forKey: "regionalPenalty") as? Double ?? UserPreferences.default.regionalPenalty,
            regionalPenaltyMult: defaults.object(forKey: "regionalPenaltyMult") as? Double ?? UserPreferences.default.regionalPenaltyMult,
            relocationPenalty: defaults.object(forKey: "relocationPenalty") as? Double ?? UserPreferences.default.relocationPenalty,
            relocationPenaltyMult: defaults.object(forKey: "relocationPenaltyMult") as? Double ?? UserPreferences.default.relocationPenaltyMult,
            internationalPenalty: defaults.object(forKey: "internationalPenalty") as? Double ?? UserPreferences.default.internationalPenalty,
            internationalPenaltyMult: defaults.object(forKey: "internationalPenaltyMult") as? Double ?? UserPreferences.default.internationalPenaltyMult,
            experiencePenalty: defaults.object(forKey: "experiencePenalty") as? Double ?? UserPreferences.default.experiencePenalty,
            credentialPenalty: defaults.object(forKey: "credentialPenalty") as? Double ?? UserPreferences.default.credentialPenalty,
            portfolioBoost: defaults.object(forKey: "portfolioBoost") as? Double ?? UserPreferences.default.portfolioBoost,
            maxSeniorityLevel: defaults.string(forKey: "maxSeniorityLevel") ?? UserPreferences.default.maxSeniorityLevel,
            professionalProfile: defaults.string(forKey: "professionalProfile") ?? UserPreferences.default.professionalProfile
        )
    }

    static func migrateLegacyCareerPrefsIfNeeded(_ defaults: UserDefaults = .standard) -> Bool {
        let current = currentFromUserDefaults(defaults)

        let staleLocations = current.preferredLocations.contains { $0.contains("Michigan") }
        let staleBroadRoles = current.preferredRoles.contains("Full Stack Engineer") || current.preferredRoles.contains("Machine Learning Engineer") || current.preferredRoles.contains("AI Engineer")
        let staleLowCutoff = current.scoreCutoff <= 0.25
        let staleProfile = current.professionalProfile.contains("healthcare operator and workflow-minded builder")

        guard staleLocations || staleBroadRoles || staleLowCutoff || staleProfile else {
            return false
        }

        let fresh = UserPreferences.default
        let encoder = JSONEncoder()

        defaults.set(fresh.minSalary, forKey: "minSalary")
        defaults.set(fresh.requireRemote, forKey: "requireRemote")
        defaults.set(fresh.locationPreference, forKey: "locationPreference")
        defaults.set(fresh.scoreCutoff, forKey: "scoreCutoff")
        defaults.set(fresh.convincingPenalty, forKey: "convincingPenalty")
        defaults.set(fresh.convincingBoost, forKey: "convincingBoost")
        defaults.set(fresh.nearbyPenalty, forKey: "nearbyPenalty")
        defaults.set(fresh.nearbyPenaltyMult, forKey: "nearbyPenaltyMult")
        defaults.set(fresh.regionalPenalty, forKey: "regionalPenalty")
        defaults.set(fresh.regionalPenaltyMult, forKey: "regionalPenaltyMult")
        defaults.set(fresh.relocationPenalty, forKey: "relocationPenalty")
        defaults.set(fresh.relocationPenaltyMult, forKey: "relocationPenaltyMult")
        defaults.set(fresh.internationalPenalty, forKey: "internationalPenalty")
        defaults.set(fresh.internationalPenaltyMult, forKey: "internationalPenaltyMult")
        defaults.set(fresh.experiencePenalty, forKey: "experiencePenalty")
        defaults.set(fresh.credentialPenalty, forKey: "credentialPenalty")
        defaults.set(fresh.portfolioBoost, forKey: "portfolioBoost")
        defaults.set(fresh.maxSeniorityLevel, forKey: "maxSeniorityLevel")
        defaults.set(fresh.professionalProfile, forKey: "professionalProfile")

        if let data = try? encoder.encode(fresh.preferredRoles),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: "preferredRolesJSON")
        }
        if let data = try? encoder.encode(fresh.excludedKeywords),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: "excludedKeywordsJSON")
        }
        if let data = try? encoder.encode(fresh.preferredLocations),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: "preferredLocationsJSON")
        }

        return true
    }
}
