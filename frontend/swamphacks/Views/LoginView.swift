//
//  LoginView.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/17/26.
//

import SwiftUI
import Auth0

struct LoginView: View {
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isAuthenticated = false
    @State private var needsProfile = false
    @State private var currentAccessToken = ""
    @State private var profileUsername = ""
    @State private var profileDisplayName = ""
    @State private var canvasCalendarURL = ""

    @StateObject private var assignmentsViewModel = AssignmentsViewModel()
    @StateObject private var profileViewModel = ProfileViewModel()

    private let credentialsManager = CredentialsManager(
        authentication: Auth0.authentication(
            clientId: Auth0Config.clientId,
            domain: Auth0Config.domain
        )
    )

    var body: some View {
        Group {
            if isAuthenticated {
                if needsProfile {
                    ProfileSetupView(
                        accessToken: currentAccessToken,
                        onProfileCreated: {
                            Task {
                                await checkProfile()
                            }
                        }
                    )
                } else {
                    MainTabView(
                        accessToken: currentAccessToken,
                        onLogout: {
                            Task {
                                await logout()
                            }
                        }
                    )
                }
            } else {
                loginScreen
            }
        }
        .task {
            await restoreSession()
        }
        .alert(
            "Authentication",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var loginScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.3.fill")
                .font(.system(size: 56))
                .foregroundStyle(.indigo)

            Text("Instigator")
                .font(.largeTitle.bold())

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    await login()
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Sign Up / Log In")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.white)
                .background(.indigo)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLoading)
        }
        .padding(24)
    }

    @MainActor
    private func logout() async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            try await Auth0
                .webAuth(
                    clientId: Auth0Config.clientId,
                    domain: Auth0Config.domain
                )
                .logout()

            try credentialsManager.clear()

            currentAccessToken = ""
            isAuthenticated = false
            needsProfile = false
            errorMessage = nil
        } catch {
            errorMessage = "Logout failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func login() async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let credentials = try await Auth0
                .webAuth(
                    clientId: Auth0Config.clientId,
                    domain: Auth0Config.domain
                )
                .audience("https://swamphacks-api")
                .start()

            try credentialsManager.store(credentials: credentials)
            currentAccessToken = credentials.accessToken
            isAuthenticated = true

            await checkProfile()
        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func restoreSession() async {
        do {
            let credentials = try await credentialsManager.credentials()
            currentAccessToken = credentials.accessToken
            isAuthenticated = true
            await checkProfile()
        } catch {
            currentAccessToken = ""
            isAuthenticated = false
            needsProfile = false
        }
    }

    @MainActor
    private func checkProfile() async {
        guard !currentAccessToken.isEmpty else {
            needsProfile = false
            return
        }

        await profileViewModel.loadProfile(
            accessToken: currentAccessToken
        )

        guard let profile = profileViewModel.profile else {
            errorMessage = profileViewModel.errorMessage
                ?? "Could not check your profile. Please try again."
            return
        }

        profileUsername = profile.username ?? ""
        profileDisplayName = profile.displayName ?? ""
        needsProfile = !(profile.profileExists ?? (profile.username != nil))
    }
}
