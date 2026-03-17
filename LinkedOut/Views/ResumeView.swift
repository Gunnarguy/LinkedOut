//
//  ResumeView.swift
//  LinkedOut
//
//  Full LinkedIn resume view — positions, education, skills, certifications.
//

import SwiftUI

struct ResumeView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var isRefreshing = false
    @State private var refreshError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let profile = auth.profile {
                    profileHeader(profile)

                    if profile.hasResumeData {
                        if !profile.positions.isEmpty {
                            experienceSection(profile.positions)
                        }
                        if !profile.education.isEmpty {
                            educationSection(profile.education)
                        }
                        if !profile.skills.isEmpty {
                            skillsSection(profile.skills)
                        }
                        if !profile.certifications.isEmpty {
                            certificationsSection(profile.certifications)
                        }
                        if !profile.languages.isEmpty {
                            languagesSection(profile.languages)
                        }
                    } else {
                        emptyState
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Resume")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshResume() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .alert("Refresh Failed", isPresented: .init(
            get: { refreshError != nil },
            set: { if !$0 { refreshError = nil } }
        )) {
            Button("OK") { refreshError = nil }
        } message: {
            Text(refreshError ?? "")
        }
    }

    // MARK: - Profile Header

    private func profileHeader(_ profile: LinkedInProfile) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                if let picUrl = URL(string: profile.profilePictureUrl),
                   !profile.profilePictureUrl.isEmpty {
                    AsyncImage(url: picUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        default:
                            initialsCircle(profile, size: 64)
                        }
                    }
                } else {
                    initialsCircle(profile, size: 64)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.fullName)
                        .font(.title3.bold())

                    if !profile.headline.isEmpty {
                        Text(profile.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !profile.email.isEmpty {
                        Text(profile.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            // Verification badges
            if !profile.verifications.isEmpty {
                HStack(spacing: 8) {
                    ForEach(profile.verifications, id: \.self) { v in
                        Label(v.replacingOccurrences(of: "_", with: " ").capitalized,
                              systemImage: "checkmark.seal.fill")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.12), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
            }

            // LinkedIn profile link
            if let url = URL(string: profile.linkedInUrl), !profile.linkedInUrl.isEmpty {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                        Text("View on LinkedIn")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, lineWidth: 0.5))
    }

    // MARK: - Experience

    private func experienceSection(_ positions: [LinkedInPosition]) -> some View {
        resumeSection(title: "Experience", icon: "briefcase.fill", iconColor: .indigo) {
            ForEach(positions) { pos in
                VStack(alignment: .leading, spacing: 6) {
                    Text(pos.title)
                        .font(.subheadline.bold())
                    Text(pos.companyName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Label(pos.dateRange, systemImage: "calendar")
                        if !pos.location.isEmpty {
                            Label(pos.location, systemImage: "mappin")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                    if pos.isCurrent {
                        Text("Current")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }

                    if !pos.description.isEmpty {
                        Text(pos.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
                .padding(.vertical, 6)

                if pos.id != positions.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Education

    private func educationSection(_ entries: [LinkedInEducation]) -> some View {
        resumeSection(title: "Education", icon: "graduationcap.fill", iconColor: .blue) {
            ForEach(entries) { edu in
                VStack(alignment: .leading, spacing: 4) {
                    Text(edu.schoolName)
                        .font(.subheadline.bold())

                    if !edu.degree.isEmpty || !edu.fieldOfStudy.isEmpty {
                        Text([edu.degree, edu.fieldOfStudy].filter { !$0.isEmpty }.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !edu.dateRange.isEmpty {
                        Label(edu.dateRange, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !edu.grade.isEmpty {
                        Text("GPA: \(edu.grade)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !edu.activities.isEmpty {
                        Text(edu.activities)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(.vertical, 6)

                if edu.id != entries.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Skills

    private func skillsSection(_ skills: [String]) -> some View {
        resumeSection(title: "Skills", icon: "star.fill", iconColor: .orange) {
            ResumeFlowLayout(spacing: 8) {
                ForEach(skills, id: \.self) { skill in
                    Text(skill)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Certifications

    private func certificationsSection(_ certs: [LinkedInCertification]) -> some View {
        resumeSection(title: "Certifications", icon: "rosette", iconColor: .purple) {
            ForEach(certs) { cert in
                VStack(alignment: .leading, spacing: 4) {
                    Text(cert.name)
                        .font(.subheadline.bold())

                    if !cert.authority.isEmpty {
                        Text(cert.authority)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !cert.licenseNumber.isEmpty {
                        Text("License: \(cert.licenseNumber)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let sy = cert.startYear {
                        let end = cert.endYear.map { "\($0)" } ?? "No Expiration"
                        Text("\(sy) – \(end)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)

                if cert.id != certs.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Languages

    private func languagesSection(_ langs: [String]) -> some View {
        resumeSection(title: "Languages", icon: "globe", iconColor: .teal) {
            ResumeFlowLayout(spacing: 8) {
                ForEach(langs, id: \.self) { lang in
                    Text(lang)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.teal.opacity(0.1), in: Capsule())
                        .foregroundStyle(.teal)
                }
            }
        }
    }

    // MARK: - Helpers

    private func resumeSection<Content: View>(
        title: String, icon: String, iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, lineWidth: 0.5))
    }

    private func initialsCircle(_ profile: LinkedInProfile, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.indigo.gradient)
                .frame(width: size, height: size)
            Text(String(profile.firstName.prefix(1)) + String(profile.lastName.prefix(1)))
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Resume Data Yet")
                .font(.headline)
            Text("Tap the refresh button to pull your full resume from LinkedIn.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await refreshResume() }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Pull from LinkedIn")
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(isRefreshing)
        }
        .padding(.vertical, 40)
    }

    private func refreshResume() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await auth.fetchResume()
        if let err = auth.error {
            refreshError = err
            auth.error = nil
        }
    }
}

// MARK: - ResumeFlowLayout (for skill/language tags)

struct ResumeFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
