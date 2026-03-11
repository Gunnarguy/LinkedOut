//
//  ServerDiscovery.swift
//  LinkedOut
//
//  Auto-discovers the backend server by probing candidate URLs.
//  Works on both Simulator (localhost) and physical devices (.local / LAN IP).
//

import Foundation

struct ServerDiscovery {
    /// Candidate URLs to probe, in priority order.
    /// Local Docker is first — it's always running at home with fresh data.
    /// Render is the fallback for when you're away from home wifi.
    static let candidates: [String] = [
        "http://Gunnars-Brain-Extension.local:8443",
        "http://10.0.0.175:8443",
        "http://localhost:8443",
        "https://linkedout-backend-9q4t.onrender.com"
    ]

    /// Probes candidate URLs in order. Returns the FIRST one that responds to /health.
    /// Uses sequential checks so the preferred .local hostname always wins if available.
    static func discover() async -> String? {
        for candidate in candidates {
            if await probe(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func probe(_ base: String) async -> Bool {
        guard let url = URL(string: "\(base)/health") else { return false }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        let session = URLSession(configuration: config)
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
