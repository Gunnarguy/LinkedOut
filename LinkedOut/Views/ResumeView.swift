//
//  ResumeView.swift
//  LinkedOut
//
//  Full LinkedIn resume viewer/editor — gorgeous liquid glass aesthetic.
//

import SwiftUI

struct ResumeView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var parallaxOffset: CGFloat = 0
    @State private var appeared = false

    // Edit mode
    @State private var isEditing = false
    @State private var editHeadline = ""
    @State private var editSkills = ""
    @State private var editLanguages = ""

    // Add new entry sheets
    @State private var showAddPosition = false
    @State private var showAddEducation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let profile = auth.profile {
                    heroHeader(profile)

                    VStack(spacing: 20) {
                        // Quick stats bar
                        statsBar(profile)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: appeared)

                        // Experience
                        sectionCard(delay: 0.15) {
                            experienceSection(profile.positions)
                        }

                        // Education
                        sectionCard(delay: 0.2) {
                            educationSection(profile.education)
                        }

                        // Skills
                        sectionCard(delay: 0.25) {
                            skillsSection(profile.skills)
                        }

                        // Certifications
                        if !profile.certifications.isEmpty {
                            sectionCard(delay: 0.3) {
                                certificationsSection(profile.certifications)
                            }
                        }

                        // Languages
                        sectionCard(delay: 0.35) {
                            languagesSection(profile.languages)
                        }

                        // Bottom spacing
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                } else {
                    emptyProfileState
                }
            }
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.indigo.opacity(0.05), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            isEditing.toggle()
                            if isEditing, let profile = auth.profile {
                                editHeadline = profile.headline
                                editSkills = profile.skills.joined(separator: ", ")
                                editLanguages = profile.languages.joined(separator: ", ")
                            }
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isEditing ? .green : .indigo)
                    }

                    Button {
                        Task { await refreshResume() }
                    } label: {
                        if isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.trianglehead.2.counterclockwise")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.indigo)
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                appeared = true
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

    // MARK: - Hero Header

    private func heroHeader(_ profile: LinkedInProfile) -> some View {
        ZStack(alignment: .bottom) {
            // Gradient backdrop
            ZStack {
                LinearGradient(
                    colors: [.indigo.opacity(0.7), .purple.opacity(0.5), .blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Subtle pattern overlay
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 300, height: 300)
                    .offset(x: 120, y: -80)
                    .blur(radius: 60)

                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .offset(x: -100, y: 20)
                    .blur(radius: 40)
            }
            .frame(height: 240)

            // Profile info overlay
            VStack(spacing: 0) {
                // Avatar
                Group {
                    if let picUrl = URL(string: profile.profilePictureUrl),
                       !profile.profilePictureUrl.isEmpty {
                        AsyncImage(url: picUrl) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                initialsView(profile, size: 100)
                            }
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                    } else {
                        initialsView(profile, size: 100)
                    }
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .offset(y: appeared ? 0 : 30)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.75), value: appeared)

                // Name
                Text(profile.fullName)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .padding(.top, 12)

                // Headline
                if isEditing {
                    TextField("Your headline", text: $editHeadline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 40)
                        .padding(.top, 4)
                } else if !profile.headline.isEmpty {
                    Text(profile.headline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 4)
                }

                // Action chips
                HStack(spacing: 10) {
                    if !profile.email.isEmpty {
                        chipButton(icon: "envelope.fill", text: profile.email, color: .white.opacity(0.2)) {
                            if let url = URL(string: "mailto:\(profile.email)") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }

                    if let url = URL(string: profile.linkedInUrl), !profile.linkedInUrl.isEmpty {
                        chipButton(icon: "link", text: "LinkedIn", color: .white.opacity(0.2)) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(.top, 12)

                // Verifications
                if !profile.verifications.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(profile.verifications, id: \.self) { v in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                Text(v.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption2.weight(.medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.25), in: Capsule())
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Stats Bar

    private func statsBar(_ profile: LinkedInProfile) -> some View {
        HStack(spacing: 0) {
            statPill(count: profile.positions.count, label: "Roles", icon: "briefcase.fill", color: .indigo)
            dividerLine
            statPill(count: profile.education.count, label: "Education", icon: "graduationcap.fill", color: .blue)
            dividerLine
            statPill(count: profile.skills.count, label: "Skills", icon: "star.fill", color: .orange)
            dividerLine
            statPill(count: profile.certifications.count, label: "Certs", icon: "rosette", color: .purple)
        }
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }

    private func statPill(count: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 32)
    }

    // MARK: - Experience

    private func experienceSection(_ positions: [LinkedInPosition]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Experience", icon: "briefcase.fill", color: .indigo)

            if positions.isEmpty {
                emptySectionPrompt(
                    icon: "building.2",
                    message: "No work experience pulled from LinkedIn yet",
                    hint: "Tap the refresh button to pull from LinkedIn, or LinkedIn may require higher API access."
                )
            } else {
                ForEach(Array(positions.enumerated()), id: \.element.id) { index, pos in
                    HStack(alignment: .top, spacing: 12) {
                        // Timeline
                        VStack(spacing: 0) {
                            Circle()
                                .fill(pos.isCurrent ? Color.green : Color.indigo.opacity(0.5))
                                .frame(width: 10, height: 10)
                                .padding(.top, 6)
                            if index < positions.count - 1 {
                                Rectangle()
                                    .fill(.quaternary)
                                    .frame(width: 1.5)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(pos.title)
                                    .font(.subheadline.bold())
                                Spacer()
                                if pos.isCurrent {
                                    Text("CURRENT")
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(0.5)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.green.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(pos.companyName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                if !pos.dateRange.isEmpty {
                                    Label(pos.dateRange, systemImage: "calendar")
                                }
                                if !pos.location.isEmpty {
                                    Label(pos.location, systemImage: "mappin")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                            if !pos.description.isEmpty {
                                Text(pos.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Education

    private func educationSection(_ entries: [LinkedInEducation]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Education", icon: "graduationcap.fill", color: .blue)

            if entries.isEmpty {
                emptySectionPrompt(
                    icon: "book.closed",
                    message: "No education data from LinkedIn yet",
                    hint: "Pull from LinkedIn or check your profile privacy settings."
                )
            } else {
                ForEach(entries) { edu in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.blue.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "building.columns")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(edu.schoolName)
                                .font(.subheadline.bold())

                            if !edu.degree.isEmpty || !edu.fieldOfStudy.isEmpty {
                                Text([edu.degree, edu.fieldOfStudy].filter { !$0.isEmpty }.joined(separator: " in "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !edu.dateRange.isEmpty {
                                Label(edu.dateRange, systemImage: "calendar")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            if !edu.grade.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.orange)
                                    Text("GPA: \(edu.grade)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if !edu.activities.isEmpty {
                                Text(edu.activities)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    if edu.id != entries.last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
    }

    // MARK: - Skills

    private func skillsSection(_ skills: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Skills", icon: "star.fill", color: .orange)

            if skills.isEmpty && !isEditing {
                emptySectionPrompt(
                    icon: "sparkles",
                    message: "No skills data yet",
                    hint: "Skills often require business-tier LinkedIn API access."
                )
            } else if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comma-separated")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("Swift, Python, FastAPI, SwiftUI...", text: $editSkills, axis: .vertical)
                        .font(.subheadline)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .lineLimit(3...6)
                }
            } else {
                ResumeFlowLayout(spacing: 8) {
                    ForEach(skills, id: \.self) { skill in
                        Text(skill)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [.blue.opacity(0.12), .indigo.opacity(0.08)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .overlay(Capsule().strokeBorder(.blue.opacity(0.15), lineWidth: 0.5))
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    // MARK: - Certifications

    private func certificationsSection(_ certs: [LinkedInCertification]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Certifications", icon: "rosette", color: .purple)

            ForEach(certs) { cert in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(.purple.opacity(0.7))
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(cert.name)
                            .font(.subheadline.bold())

                        if !cert.authority.isEmpty {
                            Text(cert.authority)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            if !cert.licenseNumber.isEmpty {
                                Text("License: \(cert.licenseNumber)")
                            }
                            if let sy = cert.startYear {
                                let end = cert.endYear.map { "\($0)" } ?? "No Expiration"
                                Text("\(sy) – \(end)")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)

                if cert.id != certs.last?.id {
                    Divider().padding(.leading, 48)
                }
            }
        }
    }

    // MARK: - Languages

    private func languagesSection(_ langs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Languages", icon: "globe", color: .teal)

            if langs.isEmpty && !isEditing {
                emptySectionPrompt(
                    icon: "character.bubble",
                    message: "No language data yet",
                    hint: "Pull from LinkedIn or add manually."
                )
            } else if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comma-separated")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("English, Spanish, French...", text: $editLanguages)
                        .font(.subheadline)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                ResumeFlowLayout(spacing: 8) {
                    ForEach(langs, id: \.self) { lang in
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                            Text(lang)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [.teal.opacity(0.12), .cyan.opacity(0.08)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(.teal.opacity(0.15), lineWidth: 0.5))
                        .foregroundStyle(.teal)
                    }
                }
            }
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            Text(title)
                .font(.headline)

            Spacer()
        }
    }

    private func sectionCard<Content: View>(delay: Double, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay), value: appeared)
    }

    private func chipButton(icon: String, text: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(text)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
        }
    }

    private func emptySectionPrompt(icon: String, message: String, hint: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.quaternary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func initialsView(_ profile: LinkedInProfile, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            Text(String(profile.firstName.prefix(1)) + String(profile.lastName.prefix(1)))
                .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var emptyProfileState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.indigo)

            Text("No Profile Yet")
                .font(.title2.bold())

            Text("Sign in with LinkedIn to pull your profile,\nor it will populate after your next connect.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task { await refreshResume() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Pull from LinkedIn")
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(isRefreshing)

            Spacer()
        }
    }

    // MARK: - Actions

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
