
import SwiftUI

struct CommitmentsView: View {
    let accessToken: String

    @StateObject private var viewModel = CommitmentsViewModel()

    @State private var title = ""
    @State private var details = ""
    @State private var selectedType = "study"
    @State private var showingCreateForm = false
    @State private var actionMessage: String?
    @State private var selectedCommitment: Commitment?
    @State private var showAllCompleted = false
    @State private var isCreating = false

    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)

    private let completedPreviewLimit = 5

    private let types = [
        "study", "assignment", "test_prep", "event", "other"
    ]

    private var activeCommitments: [Commitment] {
        viewModel.commitments.filter {
            $0.status.lowercased() != "completed"
        }
    }

    private var completedCommitments: [Commitment] {
        viewModel.commitments.filter {
            $0.status.lowercased() == "completed"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                activeSection
                loadingAndErrorSection
                invitationsSection
                participatingSection
                completedSection
            }
            .navigationTitle("Commitments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetCreateForm()
                        showingCreateForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create commitment")
                }
            }
            .task {
                await viewModel.load(accessToken: accessToken)
                await viewModel.loadInvitations(accessToken: accessToken)
                await viewModel.loadParticipatingCommitments(
                    accessToken: accessToken
                )
            }
            .sheet(isPresented: $showingCreateForm) {
                createCommitmentSheet
            }
            .sheet(item: $selectedCommitment) { commitment in
                InviteFriendsView(
                    commitment: commitment,
                    accessToken: accessToken
                )
            }
            .alert(
                "Commitments",
                isPresented: Binding(
                    get: { actionMessage != nil },
                    set: { newValue in
                        if !newValue {
                            actionMessage = nil
                        }
                    }
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

    // MARK: - Active commitments

    private var activeSection: some View {
        Section("My Commitments") {
            if activeCommitments.isEmpty && !viewModel.isLoading {
                Text("No commitments yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(activeCommitments) { commitment in
                activeCommitmentRow(commitment)
            }
        }
    }

    private func activeCommitmentRow(
        _ commitment: Commitment
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(commitment.title)
                .font(.headline)

            if let description = commitment.description,
               !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            commitmentSchedule(
                startsAt: commitment.startsAt,
                endsAt: commitment.endsAt
            )

            HStack {
                Text(formattedType(commitment.commitmentType))
                Spacer()
                Text(commitment.status.capitalized)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Invite Friends") {
                    selectedCommitment = commitment
                }
                .buttonStyle(.bordered)

                Spacer()

                if commitment.status.lowercased() != "canceled" {
                    Button("Mark Completed") {
                        completeCommitment(commitment.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Completed commitments

    private var completedSection: some View {
        Section("Completed") {
            if completedCommitments.isEmpty {
                Text("No completed commitments yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedCompletedCommitments) { commitment in
                    completedCommitmentRow(commitment)
                }

                if completedCommitments.count > completedPreviewLimit {
                    Button(showAllCompleted ? "Show less" : "View more") {
                        showAllCompleted.toggle()
                    }
                }
            }
        }
    }

    private var displayedCompletedCommitments: [Commitment] {
        if showAllCompleted {
            return completedCommitments
        }

        return Array(completedCommitments.prefix(completedPreviewLimit))
    }

    private func completedCommitmentRow(
        _ commitment: Commitment
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(commitment.title)
                .fontWeight(.medium)

            if let description = commitment.description,
               !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            commitmentSchedule(
                startsAt: commitment.startsAt,
                endsAt: commitment.endsAt
            )

            Label(
                "Completed",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Loading and errors

    @ViewBuilder
    private var loadingAndErrorSection: some View {
        if viewModel.isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        }

        if let error = viewModel.errorMessage {
            Text(error)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Invitations

    private var invitationsSection: some View {
        Section("Invitations") {
            if viewModel.invitations.isEmpty {
                Text("No pending invitations.")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.invitations) { invitation in
                invitationRow(invitation)
            }
        }
    }

    private func invitationRow(
        _ invitation: CommitmentInvitation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(invitation.title)
                .font(.headline)

            Text(
                "From \(invitation.organizerDisplayName) " +
                "(@\(invitation.organizerUsername))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Accept") {
                    respondToInvitation(
                        invitation.commitmentID,
                        accept: true
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("Decline", role: .destructive) {
                    respondToInvitation(
                        invitation.commitmentID,
                        accept: false
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Participating commitments

    private var participatingSection: some View {
        Section("Participating") {
            if viewModel.participatingCommitments.isEmpty {
                Text("You haven't joined any commitments.")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.participatingCommitments) { commitment in
                participatingCommitmentRow(commitment)
            }
        }
    }

    private func participatingCommitmentRow(
        _ commitment: ParticipatingCommitment
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commitment.title)
                .font(.headline)

            Text("Organized by \(commitment.organizerDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(formattedType(commitment.commitmentType))
                    .font(.caption)

                Spacer()

                if commitment.participationStatus == "accepted" {
                    Button("Mark Completed") {
                        completeCommitment(commitment.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Create commitment form

    private var createCommitmentSheet: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)

                    TextField(
                        "Description (optional)",
                        text: $details,
                        axis: .vertical
                    )
                    .lineLimit(3...6)

                    Picker("Type", selection: $selectedType) {
                        ForEach(types, id: \.self) { type in
                            Text(formattedType(type))
                                .tag(type)
                        }
                    }
                }

                Section("Schedule") {
                    DatePicker(
                        "Start",
                        selection: $startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    DatePicker(
                        "End",
                        selection: $endDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    if endDate <= startDate {
                        Text("The end time must be after the start time.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCreateForm = false
                    }
                    .disabled(isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createCommitment()
                    }
                    .disabled(
                        title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        || endDate <= startDate
                        || isCreating
                    )
                }
            }
        }
    }

    // MARK: - Shared helpers

    private func commitmentSchedule(
        startsAt: String?,
        endsAt: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let start = formatCommitmentDate(startsAt) {
                Label(start, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let end = formatCommitmentDate(endsAt) {
                Text("Ends \(end)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            }
        }
    }

    private func formatCommitmentDate(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        let standardFormatter = ISO8601DateFormatter()

        guard let date = fractionalFormatter.date(from: value)
            ?? standardFormatter.date(from: value) else {
            return value
        }

        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: "en_US")
        displayFormatter.timeZone = .current
        displayFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"

        return displayFormatter.string(from: date)
    }

    private func formattedType(_ type: String) -> String {
        type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func createCommitment() {
        guard endDate > startDate else {
            actionMessage = "The end time must be later than the start time."
            return
        }

        isCreating = true

        Task {
            defer {
                isCreating = false
            }

            do {
                try await viewModel.create(
                    title: title,
                    description: details,
                    type: selectedType,
                    startsAt: startDate,
                    endsAt: endDate,
                    accessToken: accessToken
                )

                resetCreateForm()
                showingCreateForm = false
            } catch {
                actionMessage = error.localizedDescription
            }
        }
    }

    private func completeCommitment(_ commitmentID: String) {
        Task {
            do {
                try await viewModel.complete(
                    commitmentID: commitmentID,
                    accessToken: accessToken
                )
            } catch {
                actionMessage = error.localizedDescription
            }
        }
    }

    private func respondToInvitation(
        _ commitmentID: String,
        accept: Bool
    ) {
        Task {
            do {
                try await viewModel.respondToInvitation(
                    commitmentID: commitmentID,
                    accept: accept,
                    accessToken: accessToken
                )
            } catch {
                actionMessage = error.localizedDescription
            }
        }
    }

    private func resetCreateForm() {
        title = ""
        details = ""
        selectedType = "study"
        startDate = Date()
        endDate = Date().addingTimeInterval(3600)
    }
}
