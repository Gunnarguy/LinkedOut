#if canImport(FoundationModels)
import Foundation
import FoundationModels

enum OnDeviceJobScoringAvailability: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .available:
            return "Apple Intelligence is available for on-device recovery."
        case .unavailable(let reason):
            return reason
        }
    }
}

enum OnDeviceJobScorer {
    static var availability: OnDeviceJobScoringAvailability {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                return .unavailable(describe(reason))
            @unknown default:
                return .unavailable("Apple Intelligence is unavailable on this device.")
            }
        }

        return .unavailable("On-device recovery requires iOS 26, macOS 26, or visionOS 26.")
    }

    static func rescore(job: JobPayload, preferences: UserPreferences) async throws -> JobPayload {
        guard availability.isAvailable else { return job }

        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let assessment = try await generateAssessment(for: job, preferences: preferences)
            return job.mergingOnDeviceAssessment(assessment)
        }

        return job
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private static func generateAssessment(
        for job: JobPayload,
        preferences: UserPreferences
    ) async throws -> AppleIntelligenceJobAssessment {
        let instructions = """
        You evaluate whether a software-related job is worth applying to for a specific candidate.
        Be factual, concise, and second-person.
        Respect the candidate's stated salary floor, remote preference, target roles, and excluded keywords.
        Return structured output only through the requested schema.
        """

        let session = LanguageModelSession(instructions: instructions)
        let prompt = buildPrompt(for: job, preferences: preferences)
        let response = try await session.respond(
            to: prompt,
            generating: AppleIntelligenceJobAssessment.self
        )
        return response.content
    }

    private static func buildPrompt(for job: JobPayload, preferences: UserPreferences) -> String {
        let description = String((job.description ?? "").prefix(3500))
        let tags = job.tags.joined(separator: ", ")
        let preferredRoles = preferences.preferredRoles.joined(separator: ", ")
        let excludedKeywords = preferences.excludedKeywords.joined(separator: ", ")
        let fitReasons = (job.fitReasons ?? []).joined(separator: ", ")
        let caveats = job.displayCaveats.joined(separator: ", ")

        return """
        Candidate profile:
        \(preferences.professionalProfile)

        Hard constraints:
        - Minimum salary: $\(preferences.minSalary)
        - Remote required: \(preferences.requireRemote)
        - Max seniority: \(preferences.maxSeniorityLevel)
        - Preferred roles: \(preferredRoles)
        - Excluded keywords: \(excludedKeywords)

        Existing job data:
        - Title: \(job.roleTitle)
        - Company: \(job.companyName)
        - Location: \(job.location)
        - Remote: \(job.isRemote)
        - Salary: \(job.salaryDisplay)
        - Existing tags: \(tags)
        - Existing fit reasons: \(fitReasons)
        - Existing caveats: \(caveats)

        Job description:
        \(description)

        Produce a sharper on-device assessment for this job.
        Keep everything concise, concrete, and directly tied to the listing.
        """
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        let raw = String(describing: reason)
        if raw.contains("deviceNotEligible") {
            return "This device does not support Apple Intelligence."
        }
        if raw.contains("appleIntelligenceNotEnabled") {
            return "Turn on Apple Intelligence to enable on-device recovery."
        }
        if raw.contains("modelNotReady") {
            return "Apple Intelligence is still downloading or not ready yet."
        }
        return "Apple Intelligence is unavailable right now."
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable(description: "Structured on-device job-match assessment for a single software job")
struct AppleIntelligenceJobAssessment {
    var builderScore: Double
    var aiPitchBullets: [String]
    var logicFit: String
    var domainLeverage: String
    var riskReward: String
    var companyOneliner: String
    var jobSnapshot: String
    var fitReasons: [String]
    var dealbreakerWarnings: [String]
    var tags: [String]
}

private extension JobPayload {
    func mergingOnDeviceAssessment(_ assessment: AppleIntelligenceJobAssessment) -> JobPayload {
        let normalizedBullets = assessment.aiPitchBullets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("•") ? $0 : "• \($0)" }

        let mergedTags = assessment.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let mergedFitReasons = assessment.fitReasons
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let mergedWarnings = assessment.dealbreakerWarnings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return JobPayload(
            id: id,
            companyName: companyName,
            roleTitle: roleTitle,
            salaryFloor: salaryFloor,
            isRemote: isRemote,
            builderScore: JobPayload.normalizedBuilderScore(
                rawScore: min(max(assessment.builderScore, 0.0), 1.0),
                scoringVersion: "apple-intelligence-v1",
                domainAlignment: domainAlignment,
                roleAlignment: roleAlignment,
                cultureFit: cultureFit,
                experienceFriction: experienceFriction,
                stackFit: stackFit
            ),
            aiPitchSummary: normalizedBullets.joined(separator: "\n"),
            draftedCoverLetter: draftedCoverLetter,
            sourceUrl: sourceUrl,
            postedAt: postedAt,
            location: location,
            tags: mergedTags.isEmpty ? tags : Array(mergedTags.prefix(5)),
            description: description,
            companyDescription: companyDescription,
            companySize: companySize,
            companyStage: companyStage,
            companyUrl: companyUrl,
            salaryMax: salaryMax,
            requirements: requirements,
            niceToHaves: niceToHaves,
            techStack: techStack,
            whyInteresting: whyInteresting,
            redFlags: redFlags,
            applyUrl: applyUrl,
            experienceLevel: experienceLevel,
            jobType: jobType,
            benefits: benefits,
            fitReasons: mergedFitReasons.isEmpty ? fitReasons : Array(mergedFitReasons.prefix(4)),
            dealbreakerWarnings: mergedWarnings.isEmpty ? dealbreakerWarnings : Array(mergedWarnings.prefix(4)),
            jobSnapshot: assessment.jobSnapshot,
            companyOneliner: assessment.companyOneliner,
            theyWant: theyWant,
            logicFit: assessment.logicFit,
            domainLeverage: assessment.domainLeverage,
            riskReward: assessment.riskReward,
            domainAlignment: domainAlignment,
            roleAlignment: roleAlignment,
            cultureFit: cultureFit,
            experienceFriction: experienceFriction,
            stackFit: stackFit,
            caveats: caveats,
            scoringVersion: "apple-intelligence-v1",
            notes: notes,
            applicationStatus: applicationStatus,
            notionPageId: notionPageId
        )
    }
}
#endif
