//
//  APIClient.swift
//  LinkedOut
//
//  Central networking layer — URLSession-based, async/await.
//

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodingError(let error):
            return "Decoding failed: \(error.localizedDescription)"
        case .networkError(let error):
            return error.localizedDescription
        }
    }

    var is404: Bool {
        if case .httpError(let code, _) = self, code == 404 { return true }
        return false
    }
}

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    /// Reads the server URL from UserDefaults (synced with Settings @AppStorage)
    private var baseURL: String {
        UserDefaults.standard.string(forKey: "serverURL") ?? "http://Gunnars-Brain-Extension.local:8443"
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Max retries for transient network errors
    private let maxRetries = 2

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        // Flexible date decoding: handles ISO 8601, fractional seconds, and space-separated
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            // Try ISO 8601 with fractional seconds first
            if let date = formatter.date(from: str) { return date }
            // Without fractional seconds
            if let date = fallbackFormatter.date(from: str) { return date }
            // Python's space-separated format: "2025-01-01 12:00:00+00:00"
            let spaceFixed = str.replacingOccurrences(of: " ", with: "T")
            if let date = formatter.date(from: spaceFixed) { return date }
            if let date = fallbackFormatter.date(from: spaceFixed) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
        }
    }

    // MARK: - Jobs

    func fetchPendingJobs(limit: Int = 20, offset: Int = 0) async throws -> [JobPayload] {
        return try await get("/api/jobs/pending?limit=\(limit)&offset=\(offset)")
    }

    func performAction(_ request: JobActionRequest) async throws -> JobActionResponse {
        return try await post("/api/jobs/action", body: request)
    }

    func fetchAppliedJobs() async throws -> [JobPayload] {
        return try await get("/api/jobs/applied")
    }

    func fetchSavedJobs() async throws -> [JobPayload] {
        return try await get("/api/jobs/saved")
    }

    func fetchRejectedJobs() async throws -> [JobPayload] {
        return try await get("/api/jobs/rejected")
    }

    func fetchStats() async throws -> StatsResponse {
        return try await get("/api/jobs/stats")
    }

    func seedMockData() async throws -> [String: Int] {
        return try await post("/api/dev/seed", body: Optional<String>.none)
    }

    // MARK: - Undo

    func undoLastAction() async throws -> UndoResponse {
        return try await post("/api/jobs/undo", body: Optional<String>.none)
    }

    // MARK: - Notes & Status

    func updateJobNotes(jobId: String, notes: String) async throws -> JobPayload {
        let body = JobNotesUpdate(notes: notes)
        return try await put("/api/jobs/\(jobId)/notes", body: body)
    }

    func updateJobStatus(jobId: String, status: String) async throws -> JobPayload {
        let body = JobStatusUpdate(status: status)
        return try await put("/api/jobs/\(jobId)/status", body: body)
    }

    // MARK: - Ingest

    func refreshIngest() async throws -> IngestResponse {
        return try await post("/api/ingest/refresh", body: Optional<String>.none)
    }

    func fetchIngestStatus() async throws -> IngestStatusResponse {
        return try await get("/api/ingest/status")
    }

    // MARK: - Re-score

    func rescoreJobs(buckets: [String] = ["pending"]) async throws -> RescoreResponse {
        let query = buckets.map { "buckets=\($0)" }.joined(separator: "&")
        return try await post("/api/jobs/rescore?\(query)", body: Optional<String>.none)
    }

    func fetchRescoreStatus() async throws -> RescoreResponse {
        return try await get("/api/jobs/rescore/status")
    }

    // MARK: - Preferences

    func syncPreferences(_ prefs: UserPreferences) async throws -> UserPreferences {
        return try await put("/api/preferences", body: prefs)
    }

    // MARK: - Auth

    func fetchLoginURL() async throws -> LoginURLResponse {
        return try await get("/auth/login")
    }

    func exchangeToken(code: String, state: String) async throws -> AuthStatusResponse {
        let req = TokenExchangeRequest(code: code, state: state)
        return try await post("/auth/token", body: req)
    }

    func checkAuthStatus(personId: String) async throws -> AuthStatusResponse {
        return try await get("/auth/status/\(personId)")
    }

    // MARK: - Share

    func shareToLinkedIn(personId: String, jobId: String, text: String = "") async throws -> [String: String] {
        var url = "/api/share?person_id=\(personId)&job_id=\(jobId)"
        if !text.isEmpty, let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            url += "&custom_text=\(encoded)"
        }
        return try await post(url, body: Optional<String>.none)
    }

    // MARK: - Notion Sync

    func configureNotion(token: String, databaseId: String) async throws -> NotionConfigureResponse {
        let body = NotionConfigureRequest(token: token, databaseId: databaseId)
        return try await post("/api/notion/configure", body: body)
    }

    func fetchNotionStatus() async throws -> NotionStatusResponse {
        return try await get("/api/notion/status")
    }

    func triggerNotionSync() async throws -> NotionSyncResponse {
        return try await post("/api/notion/sync", body: Optional<String>.none)
    }

    func triggerNotionPush() async throws -> NotionSyncResponse {
        return try await post("/api/notion/push", body: Optional<String>.none)
    }

    func triggerNotionPull() async throws -> NotionSyncResponse {
        return try await post("/api/notion/pull", body: Optional<String>.none)
    }

    func fetchNotionJobs() async throws -> [NotionJob] {
        return try await get("/api/notion/jobs")
    }

    func fetchNotionSchema() async throws -> NotionSchemaResponse {
        return try await get("/api/notion/schema")
    }

    func fetchNotionJob(pageId: String) async throws -> NotionJob {
        return try await get("/api/notion/jobs/\(pageId)")
    }

    func updateNotionJob(pageId: String, properties: [String: Any]) async throws -> NotionJob {
        guard let url = URL(string: "\(baseURL)/api/notion/jobs/\(pageId)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: properties)
        let (data, response) = try await performRequest(request)
        return try decode(data, response: response)
    }

    func deleteNotionJob(pageId: String) async throws -> [String: String] {
        guard let url = URL(string: "\(baseURL)/api/notion/jobs/\(pageId)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await performRequest(request)
        return try decode(data, response: response)
    }

    func createNotionJob(properties: [String: Any]) async throws -> NotionJob {
        guard let url = URL(string: "\(baseURL)/api/notion/jobs") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: properties)
        let (data, response) = try await performRequest(request)
        return try decode(data, response: response)
    }

    func scoreNotionJobs(rescoreAll: Bool = false) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/api/notion/score?rescore_all=\(rescoreAll)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, response) = try await performRequest(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
            throw APIError.httpError(statusCode: httpResp.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return json
    }

    func fetchNotionScoreStatus() async throws -> NotionScoreStatus {
        return try await get("/api/notion/score/status")
    }

    // MARK: - Generic HTTP

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await performRequest(URLRequest(url: url))
        return try decode(data, response: response)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B?) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await performRequest(request)
        return try decode(data, response: response)
    }

    private func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performRequest(request)
        return try decode(data, response: response)
    }

    private func performRequest(_ originalRequest: URLRequest) async throws -> (Data, URLResponse) {
        var request = originalRequest
        let method = request.httpMethod ?? "GET"

        for attempt in 0...maxRetries {
            // Bail out immediately if the task was cancelled (e.g., ViewModel switched servers)
            try Task.checkCancellation()

            let url = request.url?.absoluteString ?? "?"
            let start = CFAbsoluteTimeGetCurrent()
            if attempt > 0 {
                print("[API] 🔄 Retry \(attempt)/\(maxRetries) for \(method) \(url)")
                // Exponential backoff: 1s, 2s
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            } else {
                print("[API] ➡️ \(method) \(url)")
            }
            do {
                let (data, response) = try await session.data(for: request)
                let elapsed = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
                if let http = response as? HTTPURLResponse {
                    let size = data.count
                    print("[API] ⬅️ \(http.statusCode) \(method) \(url) — \(elapsed)ms, \(size)B")
                    // Don't retry client errors (4xx) — only server/network errors
                    if http.statusCode >= 500 && attempt < maxRetries {
                        print("[API] ⚠️ Server error \(http.statusCode), will retry...")
                        continue
                    }
                }
                return (data, response)
            } catch is CancellationError {
                print("[API] 🚫 CANCELLED \(method) \(url)")
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                print("[API] 🚫 CANCELLED \(method) \(url)")
                throw CancellationError()
            } catch {
                let elapsed = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
                print("[API] ❌ NETWORK ERROR \(method) \(url) — \(elapsed)ms — \(error.localizedDescription)")

                if attempt < maxRetries {
                    // Try re-discovering the server on network failure
                    if attempt == 0 {
                        print("[API] 🔍 Re-discovering server after network error...")
                        ServerDiscovery.invalidateCache()
                        if let found = await ServerDiscovery.discover() {
                            let current = UserDefaults.standard.string(forKey: "serverURL") ?? ""
                            if found != current {
                                print("[API] 🔄 Server URL changed: \(current) → \(found)")
                                UserDefaults.standard.set(found, forKey: "serverURL")
                                // Rebuild request with the new server URL
                                if !current.isEmpty,
                                   let oldURL = request.url?.absoluteString,
                                   let newURL = URL(string: oldURL.replacingOccurrences(of: current, with: found)) {
                                    var rebuilt = URLRequest(url: newURL)
                                    rebuilt.httpMethod = request.httpMethod
                                    rebuilt.httpBody = request.httpBody
                                    rebuilt.allHTTPHeaderFields = request.allHTTPHeaderFields
                                    request = rebuilt
                                }
                            }
                        }
                    }
                    continue
                }
                throw APIError.networkError(error)
            }
        }
        // Should not reach here, but satisfy compiler
        throw APIError.networkError(URLError(.unknown))
    }

    private func decode<T: Decodable>(_ data: Data, response: URLResponse) throws -> T {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[API] ⚠️ HTTP \(http.statusCode): \(body.prefix(300))")
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }

        do {
            let result = try decoder.decode(T.self, from: data)
            print("[API] ✅ Decoded \(T.self)")
            return result
        } catch {
            let raw = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            print("[API] 💥 DECODE FAILED for \(T.self): \(error)")
            print("[API]    Raw body: \(raw)")
            throw APIError.decodingError(error)
        }
    }
}
