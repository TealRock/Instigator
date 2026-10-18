//
//  FriendsViewModel.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//

import Foundation
import Combine

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var searchResults: [FriendUser] = []
    @Published var friends: [FriendUser] = []
    @Published var incomingRequests: [FriendRequest] = []
    @Published var outgoingRequests: [OutgoingFriendRequest] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    func searchUsers(query: String, accessToken: String) async {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanQuery.count >= 2 else {
            searchResults = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIService.searchUsers(
                query: cleanQuery,
                accessToken: accessToken
            )
            searchResults = response.users
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFriends(accessToken: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIService.fetchFriends(
                accessToken: accessToken
            )
            friends = response.friends
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadIncomingRequests(accessToken: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIService.fetchFriendRequests(
                accessToken: accessToken
            )
            incomingRequests = response.requests
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    
    func loadOutgoingRequests(accessToken: String) async {
        do {
            let response = try await APIService.fetchOutgoingFriendRequests(
                accessToken: accessToken
            )
            outgoingRequests = response.requests
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    func sendRequest(
        recipientID: String,
        accessToken: String
    ) async throws {
        try await APIService.sendFriendRequest(
            recipientID: recipientID,
            accessToken: accessToken
        )

        searchResults.removeAll { $0.id == recipientID }
        await loadIncomingRequests(accessToken: accessToken)
    }

    func acceptRequest(requesterID: String, accessToken: String) async throws {
        try await APIService.acceptFriendRequest(
            requesterID: requesterID,
            accessToken: accessToken
        )

        await loadOutgoingRequests(accessToken: accessToken)
        await loadFriends(accessToken: accessToken)
    }
    
    func rejectRequest(
        requesterID: String,
        accessToken: String
    ) async throws {
        try await APIService.rejectFriendRequest(
            requesterID: requesterID,
            accessToken: accessToken
        )

        await loadIncomingRequests(accessToken: accessToken)
    }
}
