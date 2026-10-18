//
//  ProfileSetupView.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/17/26.
//

import SwiftUI

struct ProfileSetupView: View {
    @State private var username = ""
    @State private var displayName = ""
    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    let accessToken: String
    let onProfileCreated: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Your profile") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)

                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                }

                Section {
                    Button {
                        Task {
                            await createProfile()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Create profile")
                            }
                            Spacer()
                        }
                    }
                    .disabled(
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        isSubmitting
                    )
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Set Up Profile")
        }
    }

    
    @MainActor
    private func createProfile() async {
        isSubmitting = true
        errorMessage = nil

        defer {
            isSubmitting = false
        }

        let cleanUsername = username.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let cleanDisplayName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        do {
            try await profileViewModel.createProfile(
                username: cleanUsername,
                displayName: cleanDisplayName,
                accessToken: accessToken
            )

            onProfileCreated()
        } catch {
            errorMessage = profileViewModel.errorMessage
                ?? "Could not create your profile: \(error.localizedDescription)"
        }
    }
}
