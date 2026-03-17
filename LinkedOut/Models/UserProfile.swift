//
//  UserProfile.swift
//  LinkedOut
//
//  LinkedIn profile data model.
//

import Foundation

// MARK: - LinkedIn Resume Sub-Models

struct LinkedInPosition: Codable, Identifiable {
    var id: String { "\(companyName)-\(title)-\(startYear ?? 0)" }
    let title: String
    let companyName: String
    let location: String
    let description: String
    let startYear: Int?
    let startMonth: Int?
    let endYear: Int?
    let endMonth: Int?
    let isCurrent: Bool

    enum CodingKeys: String, CodingKey {
        case title
        case companyName = "company_name"
        case location, description
        case startYear = "start_year"
        case startMonth = "start_month"
        case endYear = "end_year"
        case endMonth = "end_month"
        case isCurrent = "is_current"
    }

    var dateRange: String {
        let start = formatDate(month: startMonth, year: startYear)
        if isCurrent { return "\(start) – Present" }
        let end = formatDate(month: endMonth, year: endYear)
        return "\(start) – \(end)"
    }

    private func formatDate(month: Int?, year: Int?) -> String {
        guard let y = year else { return "?" }
        guard let m = month else { return "\(y)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        var comps = DateComponents()
        comps.month = m
        if let date = Calendar.current.date(from: comps) {
            return "\(formatter.string(from: date)) \(y)"
        }
        return "\(m)/\(y)"
    }
}

struct LinkedInEducation: Codable, Identifiable {
    var id: String { "\(schoolName)-\(degree)-\(startYear ?? 0)" }
    let schoolName: String
    let degree: String
    let fieldOfStudy: String
    let startYear: Int?
    let endYear: Int?
    let activities: String
    let grade: String

    enum CodingKeys: String, CodingKey {
        case schoolName = "school_name"
        case degree
        case fieldOfStudy = "field_of_study"
        case startYear = "start_year"
        case endYear = "end_year"
        case activities, grade
    }

    var dateRange: String {
        let s = startYear.map { "\($0)" } ?? ""
        let e = endYear.map { "\($0)" } ?? ""
        if s.isEmpty && e.isEmpty { return "" }
        return "\(s) – \(e)"
    }
}

struct LinkedInCertification: Codable, Identifiable {
    var id: String { "\(name)-\(authority)" }
    let name: String
    let authority: String
    let licenseNumber: String
    let url: String
    let startYear: Int?
    let endYear: Int?

    enum CodingKeys: String, CodingKey {
        case name, authority
        case licenseNumber = "license_number"
        case url
        case startYear = "start_year"
        case endYear = "end_year"
    }
}

// MARK: - LinkedIn Profile

struct LinkedInProfile: Codable, Identifiable {
    var id: String { personId }
    let personId: String
    let firstName: String
    let lastName: String
    let headline: String
    let vanityName: String
    let profilePictureUrl: String
    let email: String
    let profileUrl: String
    let verifications: [String]
    let positions: [LinkedInPosition]
    let education: [LinkedInEducation]
    let skills: [String]
    let certifications: [LinkedInCertification]
    let languages: [String]

    enum CodingKeys: String, CodingKey {
        case personId = "person_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case headline
        case vanityName = "vanity_name"
        case profilePictureUrl = "profile_picture_url"
        case email
        case profileUrl = "profile_url"
        case verifications, positions, education, skills, certifications, languages
    }

    // Defaults for backwards compatibility with cached profiles
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        personId = try c.decode(String.self, forKey: .personId)
        firstName = try c.decode(String.self, forKey: .firstName)
        lastName = try c.decode(String.self, forKey: .lastName)
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        vanityName = try c.decodeIfPresent(String.self, forKey: .vanityName) ?? ""
        profilePictureUrl = try c.decodeIfPresent(String.self, forKey: .profilePictureUrl) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        profileUrl = try c.decodeIfPresent(String.self, forKey: .profileUrl) ?? ""
        verifications = try c.decodeIfPresent([String].self, forKey: .verifications) ?? []
        positions = try c.decodeIfPresent([LinkedInPosition].self, forKey: .positions) ?? []
        education = try c.decodeIfPresent([LinkedInEducation].self, forKey: .education) ?? []
        skills = try c.decodeIfPresent([String].self, forKey: .skills) ?? []
        certifications = try c.decodeIfPresent([LinkedInCertification].self, forKey: .certifications) ?? []
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? []
    }

    // Memberwise init for dev mode
    init(personId: String, firstName: String, lastName: String, headline: String = "",
         vanityName: String = "", profilePictureUrl: String = "", email: String = "",
         profileUrl: String = "", verifications: [String] = [],
         positions: [LinkedInPosition] = [], education: [LinkedInEducation] = [],
         skills: [String] = [], certifications: [LinkedInCertification] = [],
         languages: [String] = []) {
        self.personId = personId
        self.firstName = firstName
        self.lastName = lastName
        self.headline = headline
        self.vanityName = vanityName
        self.profilePictureUrl = profilePictureUrl
        self.email = email
        self.profileUrl = profileUrl
        self.verifications = verifications
        self.positions = positions
        self.education = education
        self.skills = skills
        self.certifications = certifications
        self.languages = languages
    }

    var fullName: String { "\(firstName) \(lastName)" }

    var linkedInUrl: String {
        if !profileUrl.isEmpty { return profileUrl }
        if !vanityName.isEmpty { return "https://www.linkedin.com/in/\(vanityName)" }
        return ""
    }

    var hasResumeData: Bool {
        !positions.isEmpty || !education.isEmpty || !skills.isEmpty
    }
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
