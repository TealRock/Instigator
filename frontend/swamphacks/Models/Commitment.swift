//
//  Commitment.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//


import Foundation

struct Commitment: Decodable, Identifiable {
    let id: String
    let assignmentID: String?
    let commitmentType: String
    let title: String
    let description: String?
    let startsAt: String?
    let endsAt: String?
    let status: String
    let createdAt: String
    let assignmentTitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case assignmentID = "assignment_id"
        case commitmentType = "commitment_type"
        case title
        case description
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
        case createdAt = "created_at"
        case assignmentTitle = "assignment_title"
    }
}

struct CommitmentsResponse: Decodable {
    let count: Int
    let commitments: [Commitment]
}

struct CommitmentCreateRequest: Encodable {
    let title: String
    let description: String?
    let assignmentID: String?
    let commitmentType: String
    let startsAt: String?
    let endsAt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case assignmentID = "assignment_id"
        case commitmentType = "commitment_type"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }
}



struct CommitmentInvitation: Decodable, Identifiable {
    let commitmentID: String
    let title: String
    let description: String?
    let commitmentType: String
    let status: String
    let organizerUsername: String
    let organizerDisplayName: String
    let invitedAt: String

    var id: String { commitmentID }

    enum CodingKeys: String, CodingKey {
        case commitmentID = "commitment_id"
        case title, description, status
        case commitmentType = "commitment_type"
        case organizerUsername = "organizer_username"
        case organizerDisplayName = "organizer_display_name"
        case invitedAt = "invited_at"
    }
}

struct CommitmentInvitationsResponse: Decodable {
    let count: Int
    let invitations: [CommitmentInvitation]
}

struct ParticipatingCommitmentsResponse: Decodable {
    let count: Int
    let commitments: [ParticipatingCommitment]
}

struct ParticipatingCommitment: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let commitmentType: String
    let status: String
    let organizerUsername: String
    let organizerDisplayName: String
    let participationStatus: String

    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case commitmentType = "commitment_type"
        case organizerUsername = "organizer_username"
        case organizerDisplayName = "organizer_display_name"
        case participationStatus = "participation_status"
    }
}


struct CommitmentParticipantsResponse: Decodable {
    let count: Int
    let participants: [CommitmentParticipant]
}

struct CommitmentParticipant: Decodable, Identifiable {
    let userID: String
    let username: String
    let displayName: String
    let status: String
    let invitedAt: String?
    let completedAt: String?

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case status
        case invitedAt = "invited_at"
        case completedAt = "completed_at"
    }
}
