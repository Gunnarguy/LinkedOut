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
    let status: String?

    enum CodingKeys: String, CodingKey {
        case ingested
        case totalPending = "total_pending"
        case store
        case status
    }
}

struct IngestStatusResponse: Codable {
    let taskRunning: Bool
    let manualRunning: Bool
    let cycleActive: Bool?
    let lastIngestResult: Int?
    let store: StatsResponse

    enum CodingKeys: String, CodingKey {
        case taskRunning = "task_running"
        case manualRunning = "manual_running"
        case cycleActive = "cycle_active"
        case lastIngestResult = "last_ingest_result"
        case store
    }
}

// MARK: - Notion Sync

struct NotionConfigureRequest: Codable {
    let token: String
    let databaseId: String

    enum CodingKeys: String, CodingKey {
        case token
        case databaseId = "database_id"
    }
}

struct NotionConfigureResponse: Codable {
    let status: String
    let databaseId: String?
    let schema: [String: String]?
    let dataSourceId: String?
    let propertyCount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case databaseId = "database_id"
        case schema
        case dataSourceId = "data_source_id"
        case propertyCount = "property_count"
    }
}

struct NotionStatusResponse: Codable {
    let configured: Bool
    let syncRunning: Bool
    let lastSyncResult: NotionSyncStats?
    let databaseId: String?
    let hasToken: Bool
    let schema: [String: String]?
    let dataSourceId: String?
    let schemaError: String?

    enum CodingKeys: String, CodingKey {
        case configured
        case syncRunning = "sync_running"
        case lastSyncResult = "last_sync_result"
        case databaseId = "database_id"
        case hasToken = "has_token"
        case schema
        case dataSourceId = "data_source_id"
        case schemaError = "schema_error"
    }
}

struct NotionSyncStats: Codable {
    let pushed: Int?
    let updated: Int?
    let pulled: Int?
    let errors: Int?
    let error: String?
    let total: Int?
}

struct NotionSyncResponse: Codable {
    let status: String
    let stats: NotionSyncStats?
    let store: StatsResponse?
    let lastResult: NotionSyncStats?

    enum CodingKeys: String, CodingKey {
        case status
        case stats
        case store
        case lastResult = "last_result"
    }
}

struct NotionJob: Codable, Identifiable {
    let notionPageId: String
    let notionUrl: String?
    let name: String?
    let company: String?
    let role: String?
    let status: String?
    let score: Double?
    let salary: String?
    let remote: Bool?
    let location: String?
    let sourceUrl: String?
    let applyUrl: String?
    let tags: [String]?
    let techStack: [String]?
    let notes: String?
    let linkedoutId: String?
    let posted: String?
    let aiSummary: String?
    let experienceLevel: String?
    let jobType: String?
    let companyStage: String?
    let lastEdited: String?

    var id: String { notionPageId }

    enum CodingKeys: String, CodingKey {
        case notionPageId = "notion_page_id"
        case notionUrl = "notion_url"
        case name, company, role, status, score, salary
        case remote, location
        case sourceUrl = "source_url"
        case applyUrl = "apply_url"
        case tags
        case techStack = "tech_stack"
        case notes
        case linkedoutId = "linkedout_id"
        case posted
        case aiSummary = "ai_summary"
        case experienceLevel = "experience_level"
        case jobType = "job_type"
        case companyStage = "company_stage"
        case lastEdited = "last_edited"
    }
}
