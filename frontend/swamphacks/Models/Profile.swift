//
//  Profile.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//


import Foundation

struct ProfileRequest: Encodable {
    let username: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
    }
}

struct ProfileResponse: Decodable {
    let id: String?
    let username: String?
    let displayName: String?
    let createdAt: String?
    let profileExists: Bool?
    let completedCommitments: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case createdAt = "created_at"
        case profileExists = "profile_exists"
        case completedCommitments = "completed_commitments"
    }
}

struct UserSearchResponse: Decodable {
    let count: Int
    let users: [FriendUser]
}

struct FriendUser: Decodable, Identifiable {
    let id: String
    let username: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
    }
}

struct FriendsResponse: Decodable {
    let count: Int
    let friends: [FriendUser]
}

struct FriendRequestsResponse: Decodable {
    let count: Int
    let requests: [FriendRequest]
}

struct FriendRequest: Decodable, Identifiable {
    let requesterID: String
    let username: String
    let displayName: String
    let createdAt: String

    var id: String { requesterID }

    enum CodingKeys: String, CodingKey {
        case requesterID = "requester_id"
        case username
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct OutgoingFriendRequestsResponse: Decodable {
    let count: Int
    let requests: [OutgoingFriendRequest]
}

struct OutgoingFriendRequest: Decodable, Identifiable {
    let recipientID: String
    let username: String
    let displayName: String
    let createdAt: String

    var id: String { recipientID }

    enum CodingKeys: String, CodingKey {
        case recipientID = "recipient_id"
        case username
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct FriendProfileResponse: Decodable {
    let id: String
    let username: String
    let displayName: String?
    let completedCommitments: Int
    let assignments: [Assignment]
    let commitments: [FriendProfileCommitment]

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case completedCommitments = "completed_commitments"
        case assignments
        case commitments
    }
}

struct FriendProfileCommitment: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let commitmentType: String
    let startsAt: String?
    let endsAt: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case commitmentType = "commitment_type"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
    }
}
