import Foundation

// MARK: - LinkedIn Social Objects

struct LinkedInPost: Identifiable, Equatable {
    let id: String
    let urn: String
    let author: String
    let text: String
    let createdAt: Date
    let lifecycleState: String

    init(dict: [String: Any]) {
        self.urn = dict["id"] as? String ?? dict["urn"] as? String ?? UUID().uuidString
        self.id = self.urn // SwiftUI requires `id`
        self.author = dict["author"] as? String ?? ""

        if let commentary = dict["commentary"] as? String {
            self.text = commentary
        } else if let commentary = dict["commentary"] as? [String: Any],
                  let textVal = commentary["text"] as? String {
            self.text = textVal
        } else {
            self.text = ""
        }

        let ms = dict["createdAt"] as? Double ?? 0
        self.createdAt = ms > 0 ? Date(timeIntervalSince1970: ms / 1000.0) : Date()
        self.lifecycleState = dict["lifecycleState"] as? String ?? "UNKNOWN"
    }

    static func parseArray(from response: [String: Any]) -> [LinkedInPost] {
        guard let elements = response["elements"] as? [[String: Any]] else {
            return []
        }
        return elements.map { LinkedInPost(dict: $0) }
    }
}

struct LinkedInComment: Identifiable, Equatable {
    let id: String
    let urn: String
    let actor: String
    let text: String
    let createdAt: Date

    init(dict: [String: Any]) {
        self.urn = dict["id"] as? String ?? dict["urn"] as? String ?? UUID().uuidString
        self.id = self.urn
        self.actor = dict["actor"] as? String ?? ""

        if let message = dict["message"] as? [String: Any],
           let textVal = message["text"] as? String {
            self.text = textVal
        } else if let message = dict["message"] as? String {
            self.text = message
        } else {
            self.text = ""
        }

        let ms = dict["createdAt"] as? Double ?? 0
        self.createdAt = ms > 0 ? Date(timeIntervalSince1970: ms / 1000.0) : Date()
    }

    static func parseArray(from response: [String: Any]) -> [LinkedInComment] {
        guard let elements = response["elements"] as? [[String: Any]] else {
            return []
        }
        return elements.map { LinkedInComment(dict: $0) }
    }
}

struct LinkedInReaction: Identifiable, Equatable {
    let id: String
    let urn: String
    let actor: String
    let reactionType: String
    let createdAt: Date

    init(dict: [String: Any]) {
        // Reactions usually have an ID like "urn:li:reaction:123"
        let rId = dict["id"] as? String ?? dict["urn"] as? String ?? UUID().uuidString
        self.urn = rId
        self.id = rId
        self.actor = dict["actor"] as? String ?? ""
        self.reactionType = dict["reactionType"] as? String ?? "LIKE"

        let ms = dict["createdAt"] as? Double ?? dict["lastModifiedAt"] as? Double ?? 0
        self.createdAt = ms > 0 ? Date(timeIntervalSince1970: ms / 1000.0) : Date()
    }

    static func parseArray(from response: [String: Any]) -> [LinkedInReaction] {
        guard let elements = response["elements"] as? [[String: Any]] else {
            return []
        }
        return elements.map { LinkedInReaction(dict: $0) }
    }
}
