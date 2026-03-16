//
//  JobCardView.swift
//  LinkedOut
//
//  Individual swipeable job card.
//

import SwiftUI

struct JobCardView: View {
    let job: JobPayload
    var isTopCard: Bool = false
    var isNew: Bool = false
    var queuePosition: String? = nil
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(job.roleTitle)
                            .font(.title2.bold())
                            .lineLimit(2)
                        if isNew {
                            Text("NEW")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Text(job.companyName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if job.aiPitchSummary.lowercased().contains("local keyword") {
                        Text("Unscored")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.gray.opacity(0.2))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    } else {
                        ScoreRing(score: job.builderScore, size: 56, lineWidth: 5)
                    }

                    if let pos = queuePosition {
                        Text(pos)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)

            // Quick intel badges
            HStack(spacing: 6) {
                if let level = job.experienceLevel, !level.isEmpty, level != "Not specified" {
                    Text(level)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.12))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }
                if let stage = job.companyStage, !stage.isEmpty, stage != "Unknown" {
                    Text(stage)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.teal.opacity(0.12))
                        .foregroundStyle(.teal)
                        .clipShape(Capsule())
                }
                if let size = job.companySize, !size.isEmpty, size != "Unknown" {
                    Text("\(size) people")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
                if let matchLabel = job.requirementsMatchLabel {
                    HStack(spacing: 2) {
                        Image(systemName: "checklist")
                            .font(.system(size: 8))
                        Text(matchLabel)
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.indigo.opacity(0.12))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            Divider()

            // Meta row — salary, location, freshness
            HStack(spacing: 16) {
                Label(job.salaryDisplay, systemImage: "dollarsign.circle")
                    .font(.subheadline.weight(.medium))

                if job.isRemote {
                    Label("Remote", systemImage: "globe")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Label(job.location, systemImage: "mappin.circle")
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                HStack(spacing: 3) {
                    Circle()
                        .fill(freshnessColor)
                        .frame(width: 6, height: 6)
                    Text(job.freshnessLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text("via \(job.sourceName)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // ── JOB CONTENT (the actual posting) ──

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {

                    // Job description — the actual posting text
                    if let desc = job.description, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("About This Role")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(cleanHTML(desc))
                                .font(.subheadline)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Company one-liner
                    if let oneliner = job.companyOneliner, !oneliner.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "building.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            Text(oneliner)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 20)
                    } else if let compDesc = job.companyDescription, !compDesc.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "building.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            Text(compDesc)
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 20)
                    }

                    // What they're looking for — requirements
                    if let reqs = job.requirements, !reqs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What They're Looking For")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            ForEach(reqs.prefix(5), id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("·")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text(item)
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    } else if let wants = job.theyWant, !wants.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What They're Looking For")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            ForEach(wants.prefix(5), id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("·")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text(item)
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Tech stack
                    if let stack = job.techStack, !stack.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(stack.prefix(6), id: \.self) { tech in
                                    Text(tech)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.indigo.opacity(0.1))
                                        .foregroundStyle(.indigo)
                                        .clipShape(Capsule())
                                }
                                if stack.count > 6 {
                                    Text("+\(stack.count - 6)")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Job snapshot (if available — newer Why Matrix field)
                    if let snapshot = job.jobSnapshot, !snapshot.isEmpty {
                        Text(snapshot)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                    }

                    Divider()
                        .padding(.horizontal, 20)

                    // ── YOUR FIT (moved below job content) ──

                    // Fit reasons
                    if let reasons = job.fitReasons, !reasons.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(reasons.prefix(3), id: \.self) { reason in
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 8))
                                        Text(reason)
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.green.opacity(0.12))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Dealbreaker warnings
                    if let warnings = job.dealbreakerWarnings, !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(warnings.prefix(2), id: \.self) { warning in
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8))
                                        .padding(.top, 3)
                                    Text(warning)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.red.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Quick Take (AI assessment)
                    if !job.aiPitchSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quick Take")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            ForEach(job.pitchBullets.prefix(3), id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "sparkle")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .padding(.top, 2)
                                    Text(bullet.replacingOccurrences(of: "• ", with: ""))
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Tags
                    if !job.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(job.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 12)
            }

            Spacer(minLength: 0)

            // Hint footer (only on top card)
            if isTopCard {
                HStack {
                    Label("Pass", systemImage: "arrow.left")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.6))

                    Spacer()

                    Label("Save", systemImage: "arrow.up")
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.6))

                    Spacer()

                    Label("Apply", systemImage: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.green.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    // MARK: - Freshness Color

    private var freshnessColor: Color {
        guard let date = job.postedAt else { return .gray }
        let hours = -date.timeIntervalSinceNow / 3600
        if hours < 6 { return .green }        // brand new
        if hours < 24 { return .blue }         // today
        if hours < 72 { return .orange }       // last few days
        return .gray                           // older
    }

    /// Strip basic HTML entities from raw job descriptions
    private func cleanHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
