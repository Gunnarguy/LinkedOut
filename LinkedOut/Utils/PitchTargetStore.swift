import Foundation

enum PitchTargetStore {
    private static let notesKey = "pitchTargetNotes"

    static func loadTargets() -> [PitchTarget] {
        let notesByID = loadNotesByID()

        return seededTargets
            .map { target in
                var merged = target
                merged.notes = notesByID[target.id] ?? target.notes
                return merged
            }
            .sorted { lhs, rhs in
                if lhs.track != rhs.track {
                    return lhs.track.sortIndex < rhs.track.sortIndex
                }
                if lhs.priorityScore == rhs.priorityScore {
                    return lhs.companyName < rhs.companyName
                }
                return lhs.priorityScore > rhs.priorityScore
            }
    }

    static func target(withID id: String) -> PitchTarget? {
        loadTargets().first(where: { $0.id == id })
    }

    static func saveNotes(_ notes: String, for id: String) {
        var notesByID = loadNotesByID()
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            notesByID.removeValue(forKey: id)
        } else {
            notesByID[id] = notes
        }

        persist(notesByID)
    }

    static func note(for id: String) -> String {
        loadNotesByID()[id] ?? ""
    }

    private static func loadNotesByID() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: notesKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return decoded
    }

    private static func persist(_ notesByID: [String: String]) {
        guard let data = try? JSONEncoder().encode(notesByID) else { return }
        UserDefaults.standard.set(data, forKey: notesKey)
    }

    private static let seededTargets: [PitchTarget] = [
        PitchTarget(
            id: "readwise",
            track: .realisticBuyer,
            companyName: "Readwise",
            market: "Personal AI",
            websiteURL: "https://readwise.io",
            contactTarget: "Founder, Reader PM, or AI lead",
            buyerRationale: "Readwise already owns the inflow of personal knowledge, so stronger retrieval logic would compound an existing habit loop instead of forcing a new product wedge.",
            strategicFit: "OpenIntelligence fits because Readwise already captures highlights, PDFs, articles, and reading history. The missing layer is tighter local recall and context packaging that makes those artifacts feel like a real memory system instead of a pile of saved inputs.",
            priorityScore: 93,
            pitchAngle: "Pitch it as the retrieval-and-memory engine under Reader: local recall, grounded answers, and better context stitching from the user's actual corpus.",
            notes: ""
        ),
        PitchTarget(
            id: "obsidian",
            track: .realisticBuyer,
            companyName: "Obsidian",
            market: "Personal AI",
            websiteURL: "https://obsidian.md",
            contactTarget: "Founders or product lead",
            buyerRationale: "Obsidian users explicitly want local intelligence that respects the local-vault philosophy, which makes your logic unusually on-brand for them.",
            strategicFit: "OpenIntelligence fits Obsidian because the product is already built around personal knowledge, local files, and long-lived context. A first-party local retrieval layer would feel native there in a way cloud-first AI wrappers do not.",
            priorityScore: 89,
            pitchAngle: "Pitch it as the first-party local intelligence layer for vaults: retrieval, memory, and grounded answers without breaking the local-first promise.",
            notes: ""
        ),
        PitchTarget(
            id: "tana",
            track: .realisticBuyer,
            companyName: "Tana",
            market: "Knowledge Work",
            websiteURL: "https://tana.inc",
            contactTarget: "Founder or AI product lead",
            buyerRationale: "Tana is trying to turn messy inputs into structured knowledge, so a stronger retrieval layer directly improves the product rather than distracting from it.",
            strategicFit: "Tana already has the graph-like knowledge model and the right kind of power users. OpenIntelligence would strengthen the step from captured information to usable context, especially when users need higher-signal recall from a messy personal corpus.",
            priorityScore: 87,
            pitchAngle: "Pitch it as the memory-and-retrieval layer that makes Tana feel more like an intelligence system than a smart note graph.",
            notes: ""
        ),
        PitchTarget(
            id: "mem",
            track: .realisticBuyer,
            companyName: "Mem",
            market: "Personal AI",
            websiteURL: "https://mem.ai",
            contactTarget: "Founder or AI product lead",
            buyerRationale: "Mem is already selling AI-assisted memory, so better grounding and context packaging are product-level upgrades, not speculative side bets.",
            strategicFit: "OpenIntelligence fits Mem because the company already believes in turning captured notes into useful recall. Your logic helps tighten the gap between saved material and grounded answers, especially for users who need personal context rather than generic summarization.",
            priorityScore: 85,
            pitchAngle: "Pitch it as the part of Mem that makes personal recall feel sharper, more grounded, and more local than the usual chat-over-notes pattern.",
            notes: ""
        ),
        PitchTarget(
            id: "reflect",
            track: .realisticBuyer,
            companyName: "Reflect",
            market: "Personal AI",
            websiteURL: "https://reflect.app",
            contactTarget: "Founder or product lead",
            buyerRationale: "Reflect is small enough to move and close enough to the personal-memory problem that the logic is easy to explain in product terms.",
            strategicFit: "Reflect sits in the zone where users care about calm note-taking but increasingly expect more intelligence. OpenIntelligence gives them a path toward local recall, higher-signal retrieval, and better context assembly without turning the product into a noisy AI playground.",
            priorityScore: 82,
            pitchAngle: "Pitch it as a quiet but powerful local intelligence layer for note retrieval, recall, and contextual answers.",
            notes: ""
        ),
        PitchTarget(
            id: "heptabase",
            track: .realisticBuyer,
            companyName: "Heptabase",
            market: "Knowledge Work",
            websiteURL: "https://heptabase.com",
            contactTarget: "Founder or product lead",
            buyerRationale: "Heptabase is building around deep thinking and connected ideas, which makes better retrieval logic a direct product enhancement.",
            strategicFit: "Heptabase already attracts users who want more than note storage. OpenIntelligence would help convert maps, notes, and research into higher-signal contextual recall instead of leaving insight extraction to manual browsing.",
            priorityScore: 80,
            pitchAngle: "Pitch it as the context engine that turns visual knowledge work into grounded recall and usable memory.",
            notes: ""
        ),
        PitchTarget(
            id: "granola",
            track: .partnershipTarget,
            companyName: "Granola",
            market: "Personal AI",
            websiteURL: "https://www.granola.ai",
            contactTarget: "Founder, meeting intelligence lead, or product",
            buyerRationale: "Granola already owns the meeting surface, so the clearest path is a partnership or embedded-logic conversation rather than an outright buyout assumption.",
            strategicFit: "OpenIntelligence helps Granola if they want to move from single-meeting notes into durable context across meetings, docs, and prior decisions. That is a meaningful upgrade, but it reads more like a collaboration surface than an immediate acquisition target.",
            priorityScore: 88,
            pitchAngle: "Pitch it as the retrieval layer that lets Granola connect meetings to broader context, not just produce nicer notes.",
            notes: ""
        ),
        PitchTarget(
            id: "limitless",
            track: .partnershipTarget,
            companyName: "Limitless",
            market: "Personal AI",
            websiteURL: "https://www.limitless.ai",
            contactTarget: "Founder, product lead, or memory systems lead",
            buyerRationale: "Limitless is already building ambient memory, so the high-probability route is proving your retrieval logic improves that product rather than assuming they need to buy the whole thing.",
            strategicFit: "The fit is real because Limitless needs stronger grounding and context packaging to turn passive capture into useful recall. Your logic matters if it helps them answer from life history more reliably, especially on Apple-native surfaces.",
            priorityScore: 85,
            pitchAngle: "Pitch it as the retrieval and grounding layer that makes ambient memory actually actionable.",
            notes: ""
        ),
        PitchTarget(
            id: "notion",
            track: .partnershipTarget,
            companyName: "Notion",
            market: "Knowledge Work",
            websiteURL: "https://www.notion.so",
            contactTarget: "AI product lead, search PM, or partnerships",
            buyerRationale: "Notion is still relevant, but the sensible framing is partnership or integration value, not a fantasy near-term acquisition bet.",
            strategicFit: "OpenIntelligence fits because Notion AI still leaves room around offline recall, personal context, and Apple-native memory behavior. The company is large enough that licensing or feature collaboration is a more realistic first framing than 'buy my logic outright.'",
            priorityScore: 82,
            pitchAngle: "Pitch it as the layer that gives Notion AI more personal memory, local recall, and grounded context assembly on native devices.",
            notes: ""
        ),
        PitchTarget(
            id: "linear",
            track: .partnershipTarget,
            companyName: "Linear",
            market: "Knowledge Work",
            websiteURL: "https://linear.app",
            contactTarget: "AI PM, product engineering lead, or founder",
            buyerRationale: "Linear values sharp workflow logic, so there is a plausible partnership conversation around context recall even if it is not an obvious acquisition target.",
            strategicFit: "The fit is about turning issues, specs, and product context into something easier to retrieve and package. OpenIntelligence would matter if Linear wants a more opinionated context layer behind its AI features instead of thin summarization.",
            priorityScore: 79,
            pitchAngle: "Pitch it as the context engine for higher-signal product and engineering workflows, especially around local recall.",
            notes: ""
        ),
        PitchTarget(
            id: "clay",
            track: .partnershipTarget,
            companyName: "Clay",
            market: "Knowledge Work",
            websiteURL: "https://www.clay.com",
            contactTarget: "Product lead, GTM AI lead, or partnerships",
            buyerRationale: "Clay is essentially a memory-and-workflow system for people and company intelligence, so better retrieval logic has a clear place even if the end product is more GTM than personal knowledge.",
            strategicFit: "OpenIntelligence matters here if it helps turn fragmented contact, company, and workflow data into sharper context at the moment of action. The route still feels more like a product-collaboration story than a direct acquisition thesis.",
            priorityScore: 76,
            pitchAngle: "Pitch it as retrieval logic that makes Clay's people and company memory feel more grounded and context-rich.",
            notes: ""
        ),
        PitchTarget(
            id: "abridge",
            track: .partnershipTarget,
            companyName: "Abridge",
            market: "Healthcare AI",
            websiteURL: "https://www.abridge.com",
            contactTarget: "Product lead, platform lead, or strategic partnerships",
            buyerRationale: "Abridge already turns conversations into clinical outputs, so the strongest near-term angle is helping them extend from summaries into broader contextual memory.",
            strategicFit: "OpenIntelligence is relevant if Abridge wants stronger cross-encounter grounding, context reuse, or richer retrieval around prior clinical knowledge. It is believable as a workflow extension conversation, not as a casual acquisition fantasy.",
            priorityScore: 74,
            pitchAngle: "Pitch it as the retrieval-and-memory layer that extends ambient documentation into broader clinical context.",
            notes: ""
        ),
        PitchTarget(
            id: "suki",
            track: .partnershipTarget,
            companyName: "Suki",
            market: "Healthcare AI",
            websiteURL: "https://www.suki.ai",
            contactTarget: "AI product lead, platform partnerships, or corp dev",
            buyerRationale: "Suki already sells clinician workflow acceleration, so grounded context assembly is adjacent to its core value but still better framed as a partnership conversation.",
            strategicFit: "The fit is around longitudinal memory, retrieval, and context packaging across encounters and reference material. That is a useful product wedge, but the realistic path is showing workflow value first.",
            priorityScore: 71,
            pitchAngle: "Pitch it as longitudinal context packaging for clinician AI, not just another summarizer.",
            notes: ""
        ),
        PitchTarget(
            id: "glean",
            track: .aspirationalComp,
            companyName: "Glean",
            market: "Enterprise Search",
            websiteURL: "https://www.glean.com",
            contactTarget: "Use for enterprise buyer language and category framing, not as the first outbound pitch.",
            buyerRationale: "Glean validates that retrieval and knowledge access are big-category problems with real budget behind them.",
            strategicFit: "Glean matters because it shows enterprise buyers will pay for better retrieval and grounded answers. It is useful as proof that the category is valuable, even if it is not the first realistic place to assume a small inbound acquisition story.",
            priorityScore: 69,
            pitchAngle: "Use Glean as category proof when explaining why retrieval quality and context packaging are commercially important.",
            notes: ""
        ),
        PitchTarget(
            id: "sana",
            track: .aspirationalComp,
            companyName: "Sana",
            market: "Knowledge Work",
            websiteURL: "https://www.sana.ai",
            contactTarget: "Use for AI-workspace positioning and enterprise narrative calibration.",
            buyerRationale: "Sana shows there is room for AI-native knowledge work products that sell intelligence, not just note storage.",
            strategicFit: "Sana is useful because it validates the broader AI-workspace category and gives you language for how retrieval, answers, and knowledge surfaces get packaged into a product story buyers already understand.",
            priorityScore: 66,
            pitchAngle: "Use Sana as a comp when framing OpenIntelligence as a product logic layer inside AI-native knowledge work.",
            notes: ""
        ),
        PitchTarget(
            id: "hebbia",
            track: .aspirationalComp,
            companyName: "Hebbia",
            market: "Enterprise Search",
            websiteURL: "https://www.hebbia.com",
            contactTarget: "Use for knowledge-work and document-intelligence positioning, not as the first pitch list.",
            buyerRationale: "Hebbia proves that high-value document retrieval and analysis can become a real product category with strong investor belief behind it.",
            strategicFit: "Hebbia is useful because it sharpens the narrative around applied retrieval, structured reasoning, and productized knowledge work. It is more valuable as a benchmark and category validator than as a near-term buyer assumption.",
            priorityScore: 63,
            pitchAngle: "Use Hebbia to frame the market value of retrieval-heavy product logic in serious knowledge workflows.",
            notes: ""
        ),
        PitchTarget(
            id: "perplexity",
            track: .aspirationalComp,
            companyName: "Perplexity",
            market: "Personal AI",
            websiteURL: "https://www.perplexity.ai",
            contactTarget: "Use for retrieval UX language and market storytelling, not as a likely buyer target.",
            buyerRationale: "Perplexity proves there is consumer demand for products whose core value is better retrieval and answer packaging.",
            strategicFit: "Perplexity matters because it validates the user appetite for grounded answers, cited retrieval, and AI products where the experience is really about context handling. It is a category reference more than a startup-acquisition target.",
            priorityScore: 61,
            pitchAngle: "Use Perplexity as proof that retrieval quality is product value, not just backend plumbing.",
            notes: ""
        )
    ]
}
