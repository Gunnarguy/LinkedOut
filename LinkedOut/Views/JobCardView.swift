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
}
