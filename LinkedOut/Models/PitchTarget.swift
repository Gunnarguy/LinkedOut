import Foundation

enum PitchTrack: String, Codable, CaseIterable, Identifiable {
    case realisticBuyer = "Realistic Buyer"
    case partnershipTarget = "Partnership Target"
    case aspirationalComp = "Aspirational Comp"

    var id: String { rawValue }

    var sortIndex: Int {
        switch self {
        case .realisticBuyer:
            return 0
        case .partnershipTarget:
            return 1
        case .aspirationalComp:
            return 2
        }
    }

    var sectionSummary: String {
        switch self {
        case .realisticBuyer:
            return "Smaller, pitchable companies where the logic could realistically be acquired or embedded."
        case .partnershipTarget:
            return "Companies better approached through licensing, integration, or product-collaboration conversations."
        case .aspirationalComp:
            return "Category comps to sharpen your narrative, not the first places to assume an acquisition conversation."
        }
    }

    var routeTitle: String {
        switch self {
        case .realisticBuyer:
            return "Who To Pitch"
        case .partnershipTarget:
            return "Best Entry Point"
        case .aspirationalComp:
            return "How To Use This"
        }
    }

    var routeIcon: String {
        switch self {
        case .realisticBuyer:
            return "person.crop.circle.badge.plus"
        case .partnershipTarget:
            return "link.badge.plus"
        case .aspirationalComp:
            return "scope"
        }
    }

    var routeGuidance: String {
        switch self {
        case .realisticBuyer:
            return "Treat this as a direct pitch target. Lead with the logic layer, the product gap it closes, and why a small team could move quickly on it."
        case .partnershipTarget:
            return "Treat this as a partnership or licensing conversation first. The win is proving the logic fits their workflow surface before talking acquisition."
        case .aspirationalComp:
            return "Use this company as market proof and language calibration. It strengthens the story around the category, but it is not the first outbound target."
        }
    }
}

struct PitchTarget: Codable, Identifiable, Hashable {
    let id: String
    let track: PitchTrack
    let companyName: String
    let market: String
    let websiteURL: String
    let contactTarget: String
    let buyerRationale: String
    let strategicFit: String
    let priorityScore: Int
    let pitchAngle: String
    var notes: String

    var isTopPriority: Bool {
        priorityScore >= 85
    }

    var priorityLabel: String {
        switch priorityScore {
        case 90...:
            return "Very High"
        case 80...:
            return "High"
        case 70...:
            return "Medium"
        default:
            return "Watch"
        }
    }

    var priorityFraction: Double {
        Double(priorityScore) / 100.0
    }

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var searchableText: String {
        [
            track.rawValue,
            track.sectionSummary,
            companyName,
            market,
            contactTarget,
            buyerRationale,
            strategicFit,
            pitchAngle,
            notes
        ]
        .joined(separator: " ")
        .lowercased()
    }
}
