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

    enum CodingKeys: String, CodingKey {
        case minSalary = "min_salary"
        case requireRemote = "require_remote"
        case preferredRoles = "preferred_roles"
        case excludedKeywords = "excluded_keywords"
        case locationPreference = "location_preference"
    }

    static let `default` = UserPreferences(
        minSalary: 90000,
        requireRemote: true,
        preferredRoles: [
            "AI Product Engineer",
            "Founding Engineer",
            "Senior Software Engineer",
            "iOS Engineer",
            "Full Stack Engineer"
        ],
        excludedKeywords: [
            "LeetCode",
            "whiteboard",
            "competitive programming"
        ],
        locationPreference: "Remote"
    )
}
