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
    /// Candidate URLs used when the currently selected backend is unavailable.
    static let candidates: [String] = BackendConfig.discoveryCandidates

    /// How long to cache a successful discovery before re-probing.
    private static let cacheSeconds: TimeInterval = 300  // 5 minutes

    /// Last successful discovery result + timestamp.
    private nonisolated(unsafe) static var cachedURL: String?
    private nonisolated(unsafe) static var cachedAt: Date = .distantPast

    private static func select(_ url: String) -> String {
        cachedURL = url
        cachedAt = Date()
        UserDefaults.standard.set(url, forKey: "serverURL")
        return url
    }

    private static func bestHealthyCandidate(
        from candidateList: [String],
        logPrefix: String
    ) async -> String? {
        guard !candidateList.isEmpty else { return nil }

        print("[DISCOVERY] \(logPrefix)")
        let results = await withTaskGroup(of: (Int, String, Bool).self) { group in
            for (index, candidate) in candidateList.enumerated() {
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

        return results.min(by: { $0.0 < $1.0 })?.1
    }

    static func discoverPreferredNonCloudAlternative(excluding current: String) async -> String? {
        let preferredCandidates = candidates.filter {
            $0 != current && !BackendConfig.isCloud(url: $0)
        }
        guard let best = await bestHealthyCandidate(
            from: preferredCandidates,
            logPrefix: "Probing preferred non-cloud backends..."
        ) else {
            return nil
        }

        print("[DISCOVERY] Preferred non-cloud backend available: \(best)")
        return select(best)
    }

    /// Keeps the currently selected backend if it is still healthy.
    /// Otherwise probes fallback candidates in priority order and caches the winner.
    static func discover() async -> String? {
        // Return cache if still fresh — prevents oscillation between discover() calls
        if let cached = cachedURL,
           Date().timeIntervalSince(cachedAt) < cacheSeconds {
            print("[DISCOVERY] Using cached server: \(cached)")
            return cached
        }

        let current = BackendConfig.storedServerURL()
        if !current.isEmpty, await probe(current) {
            if BackendConfig.isCloud(url: current),
               let better = await discoverPreferredNonCloudAlternative(excluding: current) {
                print("[DISCOVERY] Upgraded cloud fallback \(current) → \(better)")
                return better
            }

            cachedURL = current
            cachedAt = Date()
            print("[DISCOVERY] Keeping current server: \(current)")
            return current
        }

        let fallbackCandidates = candidates.filter { $0 != current }
        if let best = await bestHealthyCandidate(
            from: fallbackCandidates,
            logPrefix: "Current server unavailable — probing fallbacks..."
        ) {
            print("[DISCOVERY] Found fallback server: \(best)")
            return select(best)
        }

        print("[DISCOVERY] 🚨 ALL candidates failed! No backend available.")
        return nil
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
