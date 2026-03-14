//
//  ServerDiscovery.swift
//  LinkedOut
//
//  Auto-discovers the backend server by probing candidate URLs.
//  Works on both Simulator (localhost) and physical devices (.local / LAN IP).
//

import Foundation

struct ServerDiscovery {
    /// Candidate URLs in priority order.
    /// Render is primary — always-on cloud server, works from any network.
    /// Local Docker is faster when on home wifi.
    static let candidates: [String] = [
        "https://linkedout-backend-9q4t.onrender.com",
        "http://Gunnars-Brain-Extension.local:8443",
        "http://10.0.0.175:8443",
        "http://localhost:8443"
    ]

    /// How long to cache a successful discovery before re-probing.
    private static let cacheSeconds: TimeInterval = 300  // 5 minutes

    /// Last successful discovery result + timestamp.
    private nonisolated(unsafe) static var cachedURL: String?
    private nonisolated(unsafe) static var cachedAt: Date = .distantPast

    /// Probes ALL candidates in parallel. Returns the highest-priority one that responds.
    /// Caches result for 5 minutes to avoid re-probing on every foreground.
    static func discover() async -> String? {
        // Return cache if fresh
        if let cached = cachedURL,
           Date().timeIntervalSince(cachedAt) < cacheSeconds {
            print("[DISCOVERY] Using cached server: \(cached)")
            return cached
        }

        // Probe all in parallel
        let results = await withTaskGroup(of: (Int, String, Bool).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let ok = await probe(candidate)
                    return (index, candidate, ok)
                }
            }
            var hits: [(Int, String)] = []
            for await (index, url, ok) in group where ok {
                hits.append((index, url))
            }
            return hits
        }

        // Pick the highest-priority (lowest index) that responded
        guard let best = results.min(by: { $0.0 < $1.0 }) else {
            return nil
        }

        cachedURL = best.1
        cachedAt = Date()
        print("[DISCOVERY] Found server: \(best.1) (probed \(results.count) OK)")
        return best.1
    }

    /// Force a fresh discovery (e.g., after network error).
    static func invalidateCache() {
        cachedAt = .distantPast
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
