//
//  FriendsView.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//

import SwiftUI

struct FriendsView: View {
    let accessToken: String
    @State private var processingRequestIDs: Set<String> = []
    @StateObject private var viewModel = FriendsViewModel()
    @State private var searchText = ""
    @State private var actionMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.incomingRequests.isEmpty {
                    Section("Incoming Requests") {
                        ForEach(viewModel.incomingRequests) { request in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(request.displayName)
                                    Text("@\(request.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    
                                    
                                    Button {
                                        respondToRequest(
                                            requesterID: request.requesterID,
                                            accept: true
                                        )
                                    } label: {
                                        Text("Accept")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.green)
                                    .disabled(processingRequestIDs.contains(request.requesterID))

                                    Button {
                                        respondToRequest(
                                            requesterID: request.requesterID,
                                            accept: false
                                        )
                                    } label: {
                                        Text("Reject")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                    .disabled(processingRequestIDs.contains(request.requesterID))


                                }
                            }
                        }
                    }
                }
                
                Section("Find Friends") {
                    TextField("Search by username or name", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, newValue in
                            Task {
                                await viewModel.searchUsers(
                                    query: newValue,
                                    accessToken: accessToken
                                )
                            }
                        }

                    ForEach(viewModel.searchResults) { user in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(user.displayName)
                                Text("@\(user.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Add") {
                                Task {
                                    do {
                                        try await viewModel.sendRequest(
                                            recipientID: user.id,
                                            accessToken: accessToken
                                        )
                                        actionMessage = "Friend request sent."
                                    } catch {
                                        actionMessage = error.localizedDescription
                                    }
                                }
                            }
                            .disabled(
                                viewModel.friends.contains { $0.id == user.id }
                            )
                        }
                    }
                }
                
                
                Section("Outgoing Requests") {
                    if viewModel.outgoingRequests.isEmpty {
                        Text("No pending outgoing requests.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.outgoingRequests) { request in
                            VStack(alignment: .leading) {
                                Text(request.displayName)
                                Text("@\(request.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Pending")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                
                
                Section("My Friends") {
                    if viewModel.friends.isEmpty {
                        Text("No friends yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.friends) { friend in
                            NavigationLink {
                                FriendProfileView(
                                    userID: friend.id,
                                    accessToken: accessToken
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friend.displayName)
                                            .fontWeight(.medium)

                                        Text("@\(friend.username)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }


                if viewModel.isLoading {
                    Section {
                        ProgressView()
                    }
                }

                if let error = viewModel.errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await refreshData()
                        }
                    }
                }
            }
            .task {
                await refreshData()
            }
            .alert(
                "Friends",
                isPresented: Binding(
                    get: { actionMessage != nil },
                    set: { if !$0 { actionMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    actionMessage = nil
                }
            } message: {
                Text(actionMessage ?? "")
            }
        }
    }
    
    private func respondToRequest(
        requesterID: String,
        accept: Bool
    ) {
        guard processingRequestIDs.insert(requesterID).inserted else {
            print("Ignored duplicate action for \(requesterID)")
            return
        }

        let action = accept ? "ACCEPT" : "REJECT"
        print("Friend request action selected: \(action), requester: \(requesterID)")

        Task {
            defer {
                processingRequestIDs.remove(requesterID)
            }

            do {
                if accept {
                    try await viewModel.acceptRequest(
                        requesterID: requesterID,
                        accessToken: accessToken
                    )
                } else {
                    try await viewModel.rejectRequest(
                        requesterID: requesterID,
                        accessToken: accessToken
                    )
                }

                print("Friend request \(action) succeeded")
                actionMessage = "Friend request \(action.lowercased())ed."
            } catch {
                print("Friend request \(action) failed: \(error)")
                actionMessage = error.localizedDescription
            }
        }
    }

    private func refreshData() async {
        await viewModel.loadFriends(accessToken: accessToken)
        await viewModel.loadIncomingRequests(accessToken: accessToken)
        await viewModel.loadOutgoingRequests(accessToken: accessToken)
    }
}
