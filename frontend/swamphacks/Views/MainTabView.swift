//
//  MainTabView.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//


import SwiftUI

struct MainTabView: View {
    let accessToken: String
    let onLogout: () -> Void

    var body: some View {
        TabView {
            ProfileTabView(
                accessToken: accessToken,
                onLogout: onLogout
            )
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }

            FriendsView(accessToken: accessToken)
                .tabItem {
                    Label("Friends", systemImage: "person.2")
                }

            CommitmentsView(accessToken: accessToken)
                .tabItem {
                    Label("Commitments", systemImage: "calendar")
                }
        }
    }
}

private struct ProfileTabView: View {
    let accessToken: String
    let onLogout: () -> Void
    
    @State private var profile: ProfileResponse?
    @State private var assignments: [Assignment] = []
    @State private var commitments: [Commitment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var showAllAssignments = false
    @State private var showAllCommitments = false

    private let previewLimit = 5
    
    private var futureAssignments: [Assignment] {
        assignments.filter { assignment in
            guard let dueDate = assignment.displayDate else {
                return false
            }
            return dueDate >= Date()
        }
    }

    private var futureCommitments: [Commitment] {
        commitments.filter { commitment in
            let dateString = commitment.endsAt ?? commitment.startsAt

            guard let dateString,
                  let date = parseDate(dateString) else {
                return false
            }

            return date >= Date()
        }
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()

        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        return formatter.date(from: value)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile?.displayName ?? "Your Profile")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("@\(profile?.username ?? "username")")
                            .foregroundStyle(.secondary)

                        Label(
                            "\(profile?.completedCommitments ?? 0) completed commitments",
                            systemImage: "checkmark.circle"
                        )
                        .padding(.top, 6)
                    }
                    .padding(.vertical, 8)
                }

                Section("Current Assignments") {
                    if futureAssignments.isEmpty {
                        Text("No assignments loaded.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(
                            Array(futureAssignments.prefix(
                                showAllAssignments ? futureAssignments.count : previewLimit
                            ))
                        ) { assignment in
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

                        if futureAssignments.count > previewLimit {
                            Button(showAllAssignments ? "Show less" : "View more") {
                                showAllAssignments.toggle()
                            }
                        }
                    }
                }

                Section("Current Commitments") {
                    if futureCommitments.isEmpty {
                        Text("No commitments yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(
                            Array(futureCommitments.prefix(
                                showAllCommitments ? futureCommitments.count : previewLimit
                            ))
                        ) { commitment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commitment.title)
                                    .fontWeight(.medium)

                                Text(commitment.status.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }

                        if futureCommitments.count > previewLimit {
                            Button(showAllCommitments ? "Show less" : "View more") {
                                showAllCommitments.toggle()
                            }
                        }                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("Loading profile…")
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await loadData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh profile")
                }
            }
            .task {
                await loadData()
            }
            .sheet(isPresented: $showingSettings) {
                ProfileSettingsView(
                    accessToken: accessToken,
                    onLogout: onLogout,
                    onAssignmentsUpdated: {
                        Task { await loadData() }
                    }
                )
            }
        }
    }

    @MainActor
    private func loadData() async {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            async let profileResult = APIService.fetchProfile(
                accessToken: accessToken
            )
            async let assignmentsResult = APIService.fetchAssignments(
                accessToken: accessToken
            )
            async let commitmentsResult = APIService.fetchCommitments(
                accessToken: accessToken
            )

            let loadedProfile = try await profileResult
            let loadedAssignments = try await assignmentsResult
            let loadedCommitments = try await commitmentsResult

            profile = loadedProfile
            assignments = loadedAssignments.assignments
            commitments = loadedCommitments.commitments
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
