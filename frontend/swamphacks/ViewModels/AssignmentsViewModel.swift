//
//  AssignmentsViewModel.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//

import Foundation
import Combine

@MainActor
final class AssignmentsViewModel: ObservableObject {
    @Published var assignments: [Assignment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadAssignments(accessToken: String) async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let response = try await APIService.fetchAssignments(
                accessToken: accessToken
            )

            assignments = response.assignments
        } catch {
            errorMessage = error.localizedDescription
            print("Could not load assignments: \(error.localizedDescription)")
        }
    }
    
    func importCanvasCalendar(
        calendarURL: String,
        accessToken: String
    ) async throws -> APIService.CanvasImportResponse {
        let response = try await APIService.importCanvasCalendar(
            calendarURL: calendarURL,
            accessToken: accessToken
        )

        await loadAssignments(accessToken: accessToken)

        return response
    }
}
