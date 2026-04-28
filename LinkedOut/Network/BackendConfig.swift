import Foundation

enum BackendConfig {
    static let piTailscaleURL = "http://gunzino.taildb93d4.ts.net:8443"
    static let localBonjourURL = "http://Gunnars-Brain-Extension.local:8443"
    static let localLoopbackURL = "http://localhost:8443"
    static let renderURL = "https://linkedout-backend-9q4t.onrender.com"

    static let discoveryCandidates: [String] = [
        piTailscaleURL,
        localBonjourURL,
        localLoopbackURL,
        renderURL,
    ]

    static let defaultServerURL = piTailscaleURL

    static func storedServerURL(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: "serverURL") ?? defaultServerURL
    }

    static func isCloud(url: String) -> Bool {
        url.contains("onrender.com")
    }

    static func isPi(url: String) -> Bool {
        url.contains("gunzino.taildb93d4.ts.net") || url.contains("100.76.130.109")
    }

    static func backendLabel(for url: String) -> String {
        if isCloud(url: url) {
            return "cloud backend"
        }
        if isPi(url: url) {
            return "pi backend"
        }
        return "local backend"
    }
}
