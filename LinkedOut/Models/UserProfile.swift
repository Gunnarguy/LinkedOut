//
//  UserProfile.swift
//  LinkedOut
//
//  LinkedIn profile data model.
//

import Foundation

struct LinkedInProfile: Codable, Identifiable {
    var id: String { personId }
    let personId: String
    let firstName: String
    let lastName: String
    let headline: String
    let vanityName: String
    let profilePictureUrl: String
    let email: String

    enum CodingKeys: String, CodingKey {
        case personId = "person_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case headline
        case vanityName = "vanity_name"
        case profilePictureUrl = "profile_picture_url"
        case email
    }

    var fullName: String { "\(firstName) \(lastName)" }
    var profileUrl: String { "https://www.linkedin.com/in/\(vanityName)" }
}

struct AuthStatusResponse: Codable {
    let authenticated: Bool
    let profile: LinkedInProfile?
}

struct LoginURLResponse: Codable {
    let authorizationUrl: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case authorizationUrl = "authorization_url"
        case state
    }
}

struct TokenExchangeRequest: Codable {
    let code: String
    let state: String
}

struct StatsResponse: Codable {
    let pending: Int
    let applied: Int
    let saved: Int
    let rejected: Int
}

struct IngestResponse: Codable {
    let ingested: Int
    let totalPending: Int
    let store: StatsResponse

    enum CodingKeys: String, CodingKey {
        case ingested
        case totalPending = "total_pending"
        case store
    }
}
