//
//  ServerDiscovery.swift
//  LinkedOut
//
//  Auto-discovers the backend server by probing candidate URLs.
//  Prefers local Docker (faster, persistent data) but falls back to
//  Render cloud so the app works anywhere without the Mac.
//

import Foundation

struct ServerDiscovery {
    /// Candidate URLs in priority order.
    /// Local Docker is preferred (faster). Render cloud is the always-on fallback.
    static let candidates: [String] = [
        "http://Gunnars-Brain-Extension.local:8443",
        "http://10.0.0.175:8443",
        "http://localhost:8443",
        "https://linkedout-backend-9q4t.onrender.com"
    ]

    /// How long to cache a successful discovery before re-probing.
    private static let cacheSeconds: TimeInterval = 300  // 5 minutes

    /// Last successful discovery result + timestamp.
    private nonisolated(unsafe) static var cachedURL: String?
    private nonisolated(unsafe) static var cachedAt: Date = .distantPast

    /// Probes ALL candidates in parallel. Returns the highest-priority one that responds.
    /// If the current server is still healthy, stays on it to avoid data disruption.
    /// Caches result for 5 minutes to avoid re-probing on every foreground.
    static func discover() async -> String? {
        // Return cache if fresh
        if let cached = cachedURL,
           Date().timeIntervalSince(cachedAt) < cacheSeconds {
            print("[DISCOVERY] Using cached server: \(cached)")
            return cached
        }

        // Check if current server is still healthy — stay on it if so
        let current = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        if !current.isEmpty, await probe(current) {
            cachedURL = current
            cachedAt = Date()
            print("[DISCOVERY] Current server still healthy: \(current)")
            return current
        }

        // Current server is down — probe all in parallel
        print("[DISCOVERY] Current server unreachable, probing all candidates...")
        let results = await withTaskGroup(of: (Int, String, Bool).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let start = Date()
                    let ok = await probe(candidate)
                    let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                    print("[DISCOVERY]   ├─ \(ok ? "✅" : "❌") \(candidate) (\(elapsed)ms)")
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
            print("[DISCOVERY] 🚨 ALL candidates failed! No backend available.")
            return nil
        }

        cachedURL = best.1
        cachedAt = Date()
        UserDefaults.standard.set(best.1, forKey: "serverURL")
        print("[DISCOVERY] Found server: \(best.1) (probed \(results.count) OK)")
        return best.1
    }

    /// Force a fresh discovery (e.g., after network error).
    static func invalidateCache() {
        print("[DISCOVERY] 🗑️ Cache invalidated — next discover() will probe fresh")
        cachedAt = .distantPast
    }

    private static func probe(_ base: String) async -> Bool {
        guard let url = URL(string: "\(base)/health") else { return false }
        let config = URLSessionConfiguration.ephemeral
        // Cloud (HTTPS) may need slightly longer than LAN
        let timeout: TimeInterval = base.hasPrefix("https") ? 5 : 2
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
