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
}

actor APIClient {
    static let shared = APIClient()

    /// Reads the server URL from UserDefaults (synced with Settings @AppStorage)
    private var baseURL: String {
        UserDefaults.standard.string(forKey: "serverURL") ?? "https://linkedout-backend-9q4t.onrender.com"
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        // Flexible date decoding: handles ISO 8601, fractional seconds, and space-separated
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
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

    func fetchStats() async throws -> StatsResponse {
        return try await get("/api/jobs/stats")
    }

    func seedMockData() async throws -> [String: Int] {
        return try await post("/api/dev/seed", body: Optional<String>.none)
    }

    // MARK: - Ingest

    func refreshIngest() async throws -> IngestResponse {
        return try await post("/api/ingest/refresh", body: Optional<String>.none)
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

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func decode<T: Decodable>(_ data: Data, response: URLResponse) throws -> T {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
