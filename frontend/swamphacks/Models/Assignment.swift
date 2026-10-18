//
//  Assignment.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//

import Foundation

struct Assignment: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let course: String?
    let courseName: String?
    let startAt: String?
    let dueAt: String?
    let location: String?
    let eventUrl: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case course
        case courseName = "course_name"
        case startAt = "start_at"
        case dueAt = "due_at"
        case location
        case eventUrl = "event_url"
        case source
    }
    
    var formattedDueDate: String? {
        guard let dueAt else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let date = isoFormatter.date(from: dueAt)
            ?? ISO8601DateFormatter().date(from: dueAt)

        guard let date else { return dueAt }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"

        return formatter.string(from: date)
    }

    
    var displayDate: Date? {
        guard let dueAt else { return nil }

        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dueAt)
    }
    
    var isUpcoming: Bool {
        guard let displayDate else { return true }
        return displayDate >= Date()
    }
}

struct AssignmentsResponse: Decodable {
    let count: Int
    let assignments: [Assignment]
}
