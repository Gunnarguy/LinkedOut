//
//  FilterSheet.swift
//  LinkedOut
//
//  Filter pending jobs by tech stack, salary, source, experience level, etc.
//

import SwiftUI

struct FilterSheet: View {
    @Binding var filters: JobFilters
    @Environment(\.dismiss) private var dismiss
    let availableTechStacks: [String]
    let availableSources: [String]

    var body: some View {
        NavigationStack {
            Form {
                // Keyword search
                Section("Search") {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Role, company, or keyword...", text: $filters.searchText)
                            .textInputAutocapitalization(.never)
                    }
                }

                // Salary minimum
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum Salary")
                            Spacer()
                            Text(filters.minSalary > 0 ? "$\(filters.minSalary / 1000)k+" : "Any")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(filters.minSalary) },
                            set: { filters.minSalary = Int($0) }
                        ), in: 0...250_000, step: 10_000)
                    }
                }

                // Experience level
                Section("Experience Level") {
                    let levels = ["Entry", "Junior", "Mid", "Senior", "Lead", "Staff"]
                    FlowLayout(spacing: 8) {
                        ForEach(levels, id: \.self) { level in
                            filterChip(level, isSelected: filters.experienceLevels.contains(level)) {
                                if filters.experienceLevels.contains(level) {
                                    filters.experienceLevels.remove(level)
                                } else {
                                    filters.experienceLevels.insert(level)
                                }
                            }
                        }
                    }
                }

                // Tech stack filter
                if !availableTechStacks.isEmpty {
                    Section("Tech Stack") {
                        FlowLayout(spacing: 8) {
                            ForEach(availableTechStacks.prefix(20), id: \.self) { tech in
                                filterChip(tech, isSelected: filters.techStacks.contains(tech)) {
                                    if filters.techStacks.contains(tech) {
                                        filters.techStacks.remove(tech)
                                    } else {
                                        filters.techStacks.insert(tech)
                                    }
                                }
                            }
                        }
                    }
                }

                // Source filter
                if !availableSources.isEmpty {
                    Section("Source") {
                        FlowLayout(spacing: 8) {
                            ForEach(availableSources, id: \.self) { source in
                                filterChip(source, isSelected: filters.sources.contains(source)) {
                                    if filters.sources.contains(source) {
                                        filters.sources.remove(source)
                                    } else {
                                        filters.sources.insert(source)
                                    }
                                }
                            }
                        }
                    }
                }

                // Score range
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum Score")
                            Spacer()
                            Text("\(Int(filters.minScore * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $filters.minScore, in: 0...1, step: 0.05)
                    }
                }

                // Clear
                Section {
                    Button("Clear All Filters", role: .destructive) {
                        filters = JobFilters()
                    }
                    .disabled(!filters.isActive)
                }
            }
            .navigationTitle("Filter Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func filterChip(_ text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? .blue : .gray.opacity(0.12))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Model

struct JobFilters {
    var searchText: String = ""
    var minSalary: Int = 0
    var minScore: Double = 0
    var experienceLevels: Set<String> = []
    var techStacks: Set<String> = []
    var sources: Set<String> = []

    var isActive: Bool {
        !searchText.isEmpty || minSalary > 0 || minScore > 0 ||
        !experienceLevels.isEmpty || !techStacks.isEmpty || !sources.isEmpty
    }

    var activeCount: Int {
        var c = 0
        if !searchText.isEmpty { c += 1 }
        if minSalary > 0 { c += 1 }
        if minScore > 0 { c += 1 }
        c += experienceLevels.count
        c += techStacks.count
        c += sources.count
        return c
    }

    func matches(_ job: JobPayload) -> Bool {
        // Keyword search
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            let searchable = "\(job.roleTitle) \(job.companyName) \(job.description ?? "") \(job.tags.joined(separator: " "))".lowercased()
            if !searchable.contains(q) { return false }
        }

        // Salary
        if minSalary > 0 && job.salaryFloor < minSalary { return false }

        // Score
        if minScore > 0 && job.builderScore < minScore { return false }

        // Experience level
        if !experienceLevels.isEmpty {
            let jobLevel = (job.experienceLevel ?? "").lowercased()
            if !experienceLevels.contains(where: { jobLevel.contains($0.lowercased()) }) {
                return false
            }
        }

        // Tech stack
        if !techStacks.isEmpty {
            let jobStack = Set((job.techStack ?? []).map { $0.lowercased() })
            if techStacks.allSatisfy({ !jobStack.contains($0.lowercased()) }) {
                return false
            }
        }

        // Source
        if !sources.isEmpty && !sources.contains(job.sourceName) {
            return false
        }

        return true
    }
}
