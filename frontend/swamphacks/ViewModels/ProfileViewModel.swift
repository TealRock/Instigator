//
//  ProfileViewModel.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//

import Foundation
import Combine

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: ProfileResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadProfile(accessToken: String) async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            profile = try await APIService.fetchProfile(
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
            print("Could not load profile: \(error.localizedDescription)")
        }
    }

    func createProfile(
        username: String,
        displayName: String,
        accessToken: String
    ) async throws {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            profile = try await APIService.createProfile(
                username: username,
                displayName: displayName,
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
