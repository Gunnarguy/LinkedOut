//
//  SettingsView.swift
//  LinkedOut
//
//  Job preferences & app settings.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("minSalary") private var minSalary: Int = 90000
    @AppStorage("requireRemote") private var requireRemote: Bool = true
    @AppStorage("locationPreference") private var locationPreference: String = "Remote"
    @AppStorage("serverURL") private var serverURL: String = "https://linkedout-backend-9q4t.onrender.com"
    @State private var preferredRoles: [String] = UserPreferences.default.preferredRoles
    @State private var excludedKeywords: [String] = UserPreferences.default.excludedKeywords
    @State private var newRole = ""
    @State private var newKeyword = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Salary") {
                    VStack(alignment: .leading) {
                        Text("Minimum: \(formattedSalary)")
                            .font(.headline)
                        Slider(
                            value: Binding(
                                get: { Double(minSalary) },
                                set: { minSalary = Int($0) }
                            ),
                            in: 50_000...300_000,
                            step: 5_000
                        )
                    }
                }

                Section("Location") {
                    Toggle("Remote Only", isOn: $requireRemote)

                    if !requireRemote {
                        TextField("Preferred Location", text: $locationPreference)
                    }
                }

                Section("Preferred Roles") {
                    ForEach(preferredRoles, id: \.self) { role in
                        Text(role)
                    }
                    .onDelete { indexSet in
                        preferredRoles.remove(atOffsets: indexSet)
                    }

                    HStack {
                        TextField("Add role...", text: $newRole)
                        Button {
                            guard !newRole.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            preferredRoles.append(newRole.trimmingCharacters(in: .whitespaces))
                            newRole = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newRole.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Excluded Keywords") {
                    ForEach(excludedKeywords, id: \.self) { kw in
                        Text(kw)
                            .foregroundStyle(.red)
                    }
                    .onDelete { indexSet in
                        excludedKeywords.remove(atOffsets: indexSet)
                    }

                    HStack {
                        TextField("Add keyword...", text: $newKeyword)
                        Button {
                            guard !newKeyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            excludedKeywords.append(newKeyword.trimmingCharacters(in: .whitespaces))
                            newKeyword = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Backend") {
                    TextField("Server URL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    Button("Reset to Defaults") {
                        let defaults = UserPreferences.default
                        minSalary = defaults.minSalary
                        requireRemote = defaults.requireRemote
                        locationPreference = defaults.locationPreference
                        preferredRoles = defaults.preferredRoles
                        excludedKeywords = defaults.excludedKeywords
                        serverURL = "https://linkedout-backend-9q4t.onrender.com"
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var formattedSalary: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: minSalary)) ?? "$\(minSalary)"
    }
}
