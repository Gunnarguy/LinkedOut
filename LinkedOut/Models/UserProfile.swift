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

struct RescoreResponse: Codable {
    let status: String
    let total: Int?
    let buckets: [String]?
    let running: Bool?
    let done: Int?
    let errors: Int?
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
    var name: String?
    var company: String?
    var role: String?
    var status: String?
    var score: Double?
    var salary: String?
    var remote: Bool?
    var location: String?
    let sourceUrl: String?
    let applyUrl: String?
    var tags: [String]?
    var techStack: [String]?
    var notes: String?
    let linkedoutId: String?
    let posted: String?
    var aiSummary: String?
    var experienceLevel: String?
    var jobType: String?
    var companyStage: String?
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

struct NotionSchemaResponse: Codable {
    let schema: [String: String]
}

struct NotionScoreStatus: Codable {
    let running: Bool
    let done: Int
    let total: Int
    let errors: Int
    let scored: Int
    let skipped: Int
}

// MARK: - Telemetry

struct TelemetryResponse: Codable {
    let timestamp: Double
    let server: TelemetryServer
    let ingest: TelemetryIngest
    let rescore: TelemetryRescore
    let notion: TelemetryNotion
    let store: TelemetryStore
    let llm: TelemetryLLM
    let logs: [String]
    let logCount: Int

    enum CodingKeys: String, CodingKey {
        case timestamp, server, ingest, rescore, notion, store, llm, logs
        case logCount = "log_count"
    }
}

struct TelemetryServer: Codable {
    let bootTime: Double
    let uptimeSeconds: Double
    let uptimeHuman: String
    let pythonVersion: String
    let hostname: String
    let port: Int
    let debug: Bool
    let render: Bool

    enum CodingKeys: String, CodingKey {
        case bootTime = "boot_time"
        case uptimeSeconds = "uptime_seconds"
        case uptimeHuman = "uptime_human"
        case pythonVersion = "python_version"
        case hostname, port, debug, render
    }
}

struct TelemetryIngest: Codable {
    let lockHeld: Bool
    let periodicTaskAlive: Bool
    let manualTaskAlive: Bool
    let lastManualResult: Int?
    let progress: IngestProgress

    enum CodingKeys: String, CodingKey {
        case lockHeld = "lock_held"
        case periodicTaskAlive = "periodic_task_alive"
        case manualTaskAlive = "manual_task_alive"
        case lastManualResult = "last_manual_result"
        case progress
    }
}

struct IngestProgress: Codable {
    let phase: String
    let batch: Int
    let totalBatches: Int
    let fetched: Int
    let newAfterDedup: Int
    let scored: Int
    let queued: Int
    let rejected: Int
    let lowScore: Int
    let errors: Int
    let startedAt: Double?
    let lastCompletedAt: Double?
    let lastDurationS: Double?
    let cyclesCompleted: Int

    enum CodingKeys: String, CodingKey {
        case phase, batch
        case totalBatches = "total_batches"
        case fetched
        case newAfterDedup = "new_after_dedup"
        case scored, queued, rejected
        case lowScore = "low_score"
        case errors
        case startedAt = "started_at"
        case lastCompletedAt = "last_completed_at"
        case lastDurationS = "last_duration_s"
        case cyclesCompleted = "cycles_completed"
    }
}

struct TelemetryRescore: Codable {
    let taskAlive: Bool
    let running: Bool
    let done: Int
    let total: Int
    let errors: Int

    enum CodingKeys: String, CodingKey {
        case taskAlive = "task_alive"
        case running, done, total, errors
    }
}

struct TelemetryNotion: Codable {
    let configured: Bool
    let syncTaskAlive: Bool
    let scoreTaskAlive: Bool

    enum CodingKeys: String, CodingKey {
        case configured
        case syncTaskAlive = "sync_task_alive"
        case scoreTaskAlive = "score_task_alive"
    }
}

struct TelemetryStore: Codable {
    let pending: Int
    let applied: Int
    let saved: Int
    let rejected: Int
    let seenUrls: Int?
    let dataDir: String

    enum CodingKeys: String, CodingKey {
        case pending, applied, saved, rejected
        case seenUrls = "seen_urls"
        case dataDir = "data_dir"
    }
}

struct TelemetryLLM: Codable {
    let provider: String
    let geminiModel: String
    let geminiFlashModel: String
    let openaiModel: String
    let hasGeminiKey: Bool
    let hasOpenaiKey: Bool

    enum CodingKeys: String, CodingKey {
        case provider
        case geminiModel = "gemini_model"
        case geminiFlashModel = "gemini_flash_model"
        case openaiModel = "openai_model"
        case hasGeminiKey = "has_gemini_key"
        case hasOpenaiKey = "has_openai_key"
    }
}
