//
//  APIService.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//

import Foundation

enum APIService {
    static var baseURL: URL {
        guard
            let configURL = Bundle.main.url(
                forResource: "AppConfig",
                withExtension: "plist"
            ),
            let data = try? Data(contentsOf: configURL),
            let config = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any],
            let urlString = config["BackendURL"] as? String,
            let url = URL(string: urlString)
        else {
            fatalError("Could not load BackendURL from AppConfig.plist.")
        }

        return url
    }
    
    static func makeRequest(
        path: String,
        method: String,
        accessToken: String,
        body: Data? = nil
    ) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        if let body {
            request.httpBody = body
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }

        return request
    }
    
    static func fetchAssignments(
        accessToken: String
    ) async throws -> AssignmentsResponse {
        let request = makeRequest(
            path: "assignments",
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "APIService",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The server returned status \(httpResponse.statusCode)."
                ]
            )
        }

        return try JSONDecoder().decode(
            AssignmentsResponse.self,
            from: data
        )
    }
    
    private struct CanvasImportRequest: Encodable {
        let calendarURL: String

        enum CodingKeys: String, CodingKey {
            case calendarURL = "calendar_url"
        }
    }

    struct CanvasImportResponse: Decodable {
        let importedCount: Int
        let message: String

        enum CodingKeys: String, CodingKey {
            case importedCount = "imported_count"
            case message
        }
    }

    static func importCanvasCalendar(
        calendarURL: String,
        accessToken: String
    ) async throws -> CanvasImportResponse {
        let body = try JSONEncoder().encode(
            CanvasImportRequest(calendarURL: calendarURL)
        )

        let request = makeRequest(
            path: "assignments/canvas/import",
            method: "POST",
            accessToken: accessToken,
            body: body
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "APIService",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Canvas import failed with status \(httpResponse.statusCode)."
                ]
            )
        }

        return try JSONDecoder().decode(
            CanvasImportResponse.self,
            from: data
        )
    }
    
    static func fetchProfile(
        accessToken: String
    ) async throws -> ProfileResponse {
        let request = makeRequest(
            path: "profile/me",
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "APIService",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Fetching profile failed with status \(httpResponse.statusCode)."
                ]
            )
        }

        return try JSONDecoder().decode(ProfileResponse.self, from: data)
    }
    
    
    static func searchUsers(
        query: String,
        accessToken: String
    ) async throws -> UserSearchResponse {
        var request = makeRequest(
            path: "users/search",
            method: "GET",
            accessToken: accessToken
        )

        guard var components = URLComponents(
            url: request.url!,
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        request.url = url

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail: String

            if let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
               let serverDetail = json["detail"] as? String {
                detail = serverDetail
            } else {
                detail = String(data: data, encoding: .utf8)
                    ?? "Unknown server error."
            }

            throw NSError(
                domain: "APIService",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(detail) (HTTP \(httpResponse.statusCode))"
                ]
            )
        }

        return try JSONDecoder().decode(
            UserSearchResponse.self,
            from: data
        )
    }

    
    static func fetchFriends(
        accessToken: String
    ) async throws -> FriendsResponse {
        let request = makeRequest(
            path: "friends",
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "APIService",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not retrieve friends."
                ]
            )
        }

        return try JSONDecoder().decode(FriendsResponse.self, from: data)
    }
    
    
    static func sendFriendRequest(
        recipientID: String,
        accessToken: String
    ) async throws {
        let request = makeRequest(
            path: "friends/request/\(recipientID)",
            method: "POST",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not send friend request."
        )
    }

    
    static func fetchFriendRequests(
        accessToken: String
    ) async throws -> FriendRequestsResponse {
        let request = makeRequest(
            path: "friends/requests",
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "APIService",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not retrieve friend requests."
                ]
            )
        }

        return try JSONDecoder().decode(FriendRequestsResponse.self, from: data)
    }
    
    static func createProfile(
        username: String,
        displayName: String,
        accessToken: String
    ) async throws -> ProfileResponse {
        let body = try JSONEncoder().encode(
            ProfileRequest(
                username: username,
                displayName: displayName
            )
        )

        let request = makeRequest(
            path: "profile",
            method: "POST",
            accessToken: accessToken,
            body: body
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "APIService",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Creating profile failed with status \(httpResponse.statusCode)."
                ]
            )
        }

        return try JSONDecoder().decode(ProfileResponse.self, from: data)
    }
    
    static func acceptFriendRequest(
        requesterID: String,
        accessToken: String
    ) async throws {
        let encodedID = requesterID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? requesterID

        let request = makeRequest(
            path: "friends/requests/\(encodedID)/accept",
            method: "POST",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(
            response,
            data: data,
            failureMessage: "Friend request action failed."
        )
    }
    
    static func rejectFriendRequest(
        requesterID: String,
        accessToken: String
    ) async throws {
        let request = makeRequest(
            path: "friends/requests/\(requesterID)/reject",
            method: "POST",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(
            response,
            data: data,
            failureMessage: "Friend request action failed."
        )
    }
    
    static func fetchOutgoingFriendRequests(
        accessToken: String
    ) async throws -> OutgoingFriendRequestsResponse {
        let request = makeRequest(
            path: "friends/outgoing-requests",
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not load outgoing requests."
        )

        return try JSONDecoder().decode(
            OutgoingFriendRequestsResponse.self,
            from: data
        )
    }
    
    
    static func fetchCommitments(
        accessToken: String
    ) async throws -> CommitmentsResponse {
        let request = makeRequest(
            path: "commitments",
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not load commitments."
        )

        return try JSONDecoder().decode(CommitmentsResponse.self, from: data)
    }

    static func createCommitment(
        _ commitment: CommitmentCreateRequest,
        accessToken: String
    ) async throws {
        let body = try JSONEncoder().encode(commitment)

        let request = makeRequest(
            path: "commitments",
            method: "POST",
            accessToken: accessToken,
            body: body
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not create commitment."
        )
    }

    
    static func fetchCommitmentInvitations(
        accessToken: String
    ) async throws -> CommitmentInvitationsResponse {
        let request = makeRequest(
            path: "commitments/invitations",
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not load commitment invitations."
        )
        return try JSONDecoder().decode(
            CommitmentInvitationsResponse.self,
            from: data
        )
    }

    
    static func respondToCommitmentInvitation(
        commitmentID: String,
        accept: Bool,
        accessToken: String
    ) async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(
                "commitments/\(commitmentID)/respond"
            ),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(
                name: "accept",
                value: accept ? "true" : "false"
            )
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not respond to invitation."
        )
    }


    static func fetchParticipatingCommitments(
        accessToken: String
    ) async throws -> ParticipatingCommitmentsResponse {
        let request = makeRequest(
            path: "commitments/participating",
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not load participating commitments."
        )
        return try JSONDecoder().decode(
            ParticipatingCommitmentsResponse.self,
            from: data
        )
    }

    
    static func inviteFriendToCommitment(
        commitmentID: String,
        userID: String,
        accessToken: String
    ) async throws {
        let request = makeRequest(
            path: "commitments/\(commitmentID)/invite/\(userID)",
            method: "POST",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not invite friend."
        )
    }

    static func fetchCommitmentParticipants(
        commitmentID: String,
        accessToken: String
    ) async throws -> CommitmentParticipantsResponse {
        let request = makeRequest(
            path: "commitments/\(commitmentID)/participants",
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not load commitment participants."
        )

        return try JSONDecoder().decode(
            CommitmentParticipantsResponse.self,
            from: data
        )
    }
    
    
    static func fetchFriendProfile(
        userID: String,
        accessToken: String
    ) async throws -> FriendProfileResponse {
        let path = "users/\(userID)/profile"
        let request = makeRequest(
            path: path,
            method: "GET",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data, failureMessage: "Failed to fetch friend profile.")

        return try JSONDecoder().decode(
            FriendProfileResponse.self,
            from: data
        )
    }

    
    static func completeCommitment(
        commitmentID: String,
        accessToken: String
    ) async throws {
        let request = makeRequest(
            path: "commitments/\(commitmentID)/complete",
            method: "POST",
            accessToken: accessToken
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(
            response,
            data: data,
            failureMessage: "Could not complete commitment."
        )
    }

    
    private static func validateResponse(
        _ response: URLResponse,
        data: Data,
        failureMessage: String
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "APIService",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid server response."
                ]
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var detail = failureMessage

            if let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
               let serverDetail = json["detail"] as? String {
                detail = serverDetail
            }

            throw NSError(
                domain: "APIService",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(detail) (HTTP \(httpResponse.statusCode))"
                ]
            )
        }
    }
}
