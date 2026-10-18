//
//  ProfileSettingsView.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//


import SwiftUI

struct ProfileSettingsView: View {
    let accessToken: String
    let onLogout: () -> Void
    let onAssignmentsUpdated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var calendarURL = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Canvas Calendar") {
                    TextField(
                        "Canvas calendar subscription URL",
                        text: $calendarURL,
                        axis: .vertical
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                    Button("Import Calendar") {
                        Task { await importCalendar() }
                    }
                    .disabled(isWorking || calendarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Assignments") {
                    Button("Load Assignments") {
                        Task { await loadAssignments() }
                    }
                    .disabled(isWorking)

                    Text("Refreshes the assignments currently available from your account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Account") {
                    Button("Log Out", role: .destructive) {
                        onLogout()
                    }
                }

                if isWorking {
                    Section {
                        ProgressView()
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @MainActor
    private func importCalendar() async {
        isWorking = true
        message = nil
        errorMessage = nil
        defer { isWorking = false }

        do {
            let result = try await APIService.importCanvasCalendar(
                calendarURL: calendarURL.trimmingCharacters(in: .whitespacesAndNewlines),
                accessToken: accessToken
            )
            message = result.message
            onAssignmentsUpdated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadAssignments() async {
        isWorking = true
        message = nil
        errorMessage = nil
        defer { isWorking = false }

        do {
            let result = try await APIService.fetchAssignments(
                accessToken: accessToken
            )
            message = "Loaded \(result.count) assignments."
            onAssignmentsUpdated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
