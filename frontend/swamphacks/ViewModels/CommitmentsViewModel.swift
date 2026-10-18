//
//  CommitmentsViewModel.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//


import Foundation
import Combine

@MainActor
final class CommitmentsViewModel: ObservableObject {
    @Published var commitments: [Commitment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var invitations: [CommitmentInvitation] = []
    @Published var participatingCommitments: [ParticipatingCommitment] = []
    @Published var friends: [FriendUser] = []
    @Published var participants: [CommitmentParticipant] = []
    @Published var inviteMessage: String?

    func load(accessToken: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await APIService.fetchCommitments(
                accessToken: accessToken
            )
            commitments = response.commitments
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(
        title: String,
        description: String,
        type: String,
        startsAt: Date,
        endsAt: Date,
        accessToken: String
    ) async throws {
        guard endsAt > startsAt else {
            throw NSError(
                domain: "Commitments",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The end time must be later than the start time."
                ]
            )
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let request = CommitmentCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : description,
            assignmentID: nil,
            commitmentType: type,
            startsAt: formatter.string(from: startsAt),
            endsAt: formatter.string(from: endsAt)
        )

        try await APIService.createCommitment(
            request,
            accessToken: accessToken
        )

        await load(accessToken: accessToken)
    }
    
    
    func loadInvitations(accessToken: String) async {
        do {
            let response = try await APIService.fetchCommitmentInvitations(
                accessToken: accessToken
            )
            invitations = response.invitations
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadParticipatingCommitments(accessToken: String) async {
        do {
            let response = try await APIService.fetchParticipatingCommitments(
                accessToken: accessToken
            )
            participatingCommitments = response.commitments
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respondToInvitation(
        commitmentID: String,
        accept: Bool,
        accessToken: String
    ) async throws {
        try await APIService.respondToCommitmentInvitation(
            commitmentID: commitmentID,
            accept: accept,
            accessToken: accessToken
        )

        await loadInvitations(accessToken: accessToken)
        await loadParticipatingCommitments(accessToken: accessToken)
    }
    
    
    func loadFriends(accessToken: String) async {
        do {
            let response = try await APIService.fetchFriends(
                accessToken: accessToken
            )
            friends = response.friends
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadParticipants(
        commitmentID: String,
        accessToken: String
    ) async {
        do {
            let response = try await APIService.fetchCommitmentParticipants(
                commitmentID: commitmentID,
                accessToken: accessToken
            )
            participants = response.participants
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func inviteFriend(
        userID: String,
        commitmentID: String,
        accessToken: String
    ) async throws {
        try await APIService.inviteFriendToCommitment(
            commitmentID: commitmentID,
            userID: userID,
            accessToken: accessToken
        )

        await loadParticipants(
            commitmentID: commitmentID,
            accessToken: accessToken
        )
    }
    
    
    func complete(
        commitmentID: String,
        accessToken: String
    ) async throws {
        try await APIService.completeCommitment(
            commitmentID: commitmentID,
            accessToken: accessToken
        )

        await load(accessToken: accessToken)
        await loadParticipatingCommitments(accessToken: accessToken)
    }
}



