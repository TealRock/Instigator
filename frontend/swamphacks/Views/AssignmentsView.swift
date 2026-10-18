//
//  AssignmentsView.swift
//  Instigator
//
//  Created by Christian Caraballo on 10/18/26.
//

import SwiftUI

struct AssignmentsView: View {
    @State private var selectedFilter = "Upcoming"
    let assignments: [Assignment]
    
    private var filteredAssignments: [Assignment] {
        if selectedFilter == "Upcoming" {
            return assignments.filter { $0.isUpcoming }
        } else {
            return assignments.filter { !$0.isUpcoming }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Assignments: \(assignments.count)")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                Picker("Assignment Filter", selection: $selectedFilter) {
                    Text("Upcoming").tag("Upcoming")
                    Text("Past").tag("Past")
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)
                
                ForEach(filteredAssignments) { assignment in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(assignment.title)
                            .font(.body)
                            .lineLimit(2)
                        
                        if let displayDate = assignment.displayDate {
                            let formattedDate = displayDate.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )

                            Text("Date: \(formattedDate)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        if let courseName = assignment.courseName {
                            Text(courseName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                    
                    Divider()
                }
            }
        }
    }
}
