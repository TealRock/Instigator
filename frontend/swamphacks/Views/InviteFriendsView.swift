//
//  InviteFriendsView.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//


import SwiftUI

struct InviteFriendsView: View {
    let commitment: Commitment
    let accessToken: String

    @StateObject private var viewModel = CommitmentsViewModel()
    @State private var invitingUserIDs: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Invite Friends") {
                    if viewModel.friends.isEmpty {
                        Text("No friends to invite yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.friends) { friend in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(friend.displayName)
                                Text("@\(friend.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            let participant = viewModel.participants.first {
                                $0.userID == friend.id
                            }

                            if let participant {
                                Text(participant.status.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Invite") {
                                    sendInvitation(to: friend)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(invitingUserIDs.contains(friend.id))
                            }
                        }
                    }
                }

                Section("Participants") {
                    if viewModel.participants.isEmpty {
                        Text("No participants yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.participants) { participant in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(participant.displayName)
                            Text("@\(participant.username) · \(participant.status.capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Invite Friends")
            .task {
                await viewModel.loadFriends(accessToken: accessToken)
                await viewModel.loadParticipants(
                    commitmentID: commitment.id,
                    accessToken: accessToken
                )
            }
            .alert(
                "Invitation",
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
    }

    private func sendInvitation(to friend: FriendUser) {
        guard invitingUserIDs.insert(friend.id).inserted else {
            return
        }

        Task {
            defer { invitingUserIDs.remove(friend.id) }

            do {
                try await viewModel.inviteFriend(
                    userID: friend.id,
                    commitmentID: commitment.id,
                    accessToken: accessToken
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
