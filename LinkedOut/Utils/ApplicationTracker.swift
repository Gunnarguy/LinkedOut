//
//  ApplicationTracker.swift
//  LinkedOut
//
//  Tracks when the user applied to each job (local timestamps).
//

import Foundation

enum ApplicationTracker {
    private static let key = "applicationTimestamps"

    /// Record that the user applied to this job right now
    static func markApplied(jobId: String) {
        var timestamps = loadAll()
        timestamps[jobId] = Date()
        save(timestamps)
    }

    /// Get the date the user applied to this job, if any
    static func appliedDate(for jobId: String) -> Date? {
        loadAll()[jobId]
    }

    /// "Applied 3 days ago" label for a job
    static func appliedAgoLabel(for jobId: String) -> String? {
        guard let date = appliedDate(for: jobId) else { return nil }
        let seconds = -date.timeIntervalSinceNow
        switch seconds {
        case ..<60:       return "Applied just now"
        case ..<3600:     return "Applied \(Int(seconds / 60))m ago"
        case ..<86400:    return "Applied \(Int(seconds / 3600))h ago"
        case ..<604800:   return "Applied \(Int(seconds / 86400))d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "Applied \(formatter.string(from: date))"
        }
    }

    /// "Follow up?" hint if applied more than 5 days ago
    static func shouldFollowUp(jobId: String) -> Bool {
        guard let date = appliedDate(for: jobId) else { return false }
        return -date.timeIntervalSinceNow > 5 * 86400
    }

    private static func loadAll() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ timestamps: [String: Date]) {
        guard let data = try? JSONEncoder().encode(timestamps) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
