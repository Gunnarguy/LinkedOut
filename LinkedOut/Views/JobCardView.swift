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
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.roleTitle)
                        .font(.title2.bold())
                        .lineLimit(2)

                    Text(job.companyName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ScoreRing(score: job.builderScore, size: 56, lineWidth: 5)
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            // Fit reasons — WHY this job matches Gunnar
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
                .padding(.bottom, 4)
            }

            // Dealbreaker warnings — honest heads-up about potential rejection risks
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
                .padding(.bottom, 4)
            }

            Divider()

            // Meta row
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

                // Freshness indicator
                HStack(spacing: 3) {
                    Circle()
                        .fill(freshnessColor)
                        .frame(width: 6, height: 6)
                    Text(job.freshnessLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // AI Pitch
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Assessment")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(job.pitchBullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(.top, 2)

                        Text(bullet.replacingOccurrences(of: "• ", with: ""))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            // Tech stack preview (first 4)
            if let stack = job.techStack, !stack.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(stack.prefix(5), id: \.self) { tech in
                            Text(tech)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.indigo.opacity(0.1))
                                .foregroundStyle(.indigo)
                                .clipShape(Capsule())
                        }
                        if stack.count > 5 {
                            Text("+\(stack.count - 5)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)
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
                .padding(.bottom, 16)
            }

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
}
