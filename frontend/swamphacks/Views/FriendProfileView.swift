//
//  FriendProfileView.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//


import SwiftUI

struct FriendProfileView: View {
    let userID: String
    let accessToken: String

    @State private var profile: FriendProfileResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let previewLimit = 5

    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading profile…")
            } else if let profile {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)

                        Text(profile.displayName ?? profile.username)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("@\(profile.username)")
                            .foregroundStyle(.secondary)

                        Label(
                            "\(profile.completedCommitments) completed commitments",
                            systemImage: "checkmark.circle"
                        )
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }

                Section("Upcoming Assignments") {
                    if profile.assignments.isEmpty {
                        Text("No upcoming assignments.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profile.assignments.prefix(previewLimit)) { assignment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(assignment.title)
                                    .fontWeight(.medium)

                                if let course = assignment.courseName ?? assignment.course {
                                    Text(course)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if let dueDate = assignment.formattedDueDate {
                                    Label(dueDate, systemImage: "clock")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }

                        if profile.assignments.count > previewLimit {
                            NavigationLink("View all assignments") {
                                FriendAssignmentsListView(
                                    assignments: profile.assignments
                                )
                            }
                        }
                    }
                }

                Section("Current Commitments") {
                    if profile.commitments.isEmpty {
                        Text("No current commitments.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profile.commitments.prefix(previewLimit)) { commitment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commitment.title)
                                    .fontWeight(.medium)

                                Text(commitment.status.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if let date = commitment.startsAt {
                                    Text(date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }

                        if profile.commitments.count > previewLimit {
                            NavigationLink("View all commitments") {
                                FriendCommitmentsListView(
                                    commitments: profile.commitments
                                )
                            }
                        }
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "Could Not Load Profile",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(errorMessage)
                )
            }
        }
        .navigationTitle("Friend Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfile()
        }
    }

    @MainActor
    private func loadProfile() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            profile = try await APIService.fetchFriendProfile(
                userID: userID,
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FriendAssignmentsListView: View {
    let assignments: [Assignment]

    var body: some View {
        List(assignments) { assignment in
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.title)
                    .fontWeight(.medium)

                if let dueDate = assignment.formattedDueDate {
                    Text(dueDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Assignments")
    }
}

private struct FriendCommitmentsListView: View {
    let commitments: [FriendProfileCommitment]

    var body: some View {
        List(commitments) { commitment in
            VStack(alignment: .leading, spacing: 4) {
                Text(commitment.title)
                    .fontWeight(.medium)

                Text(commitment.status.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Commitments")
    }
}
