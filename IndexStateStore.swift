//
//  IndexStateStore.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/07.
//

import SwiftData
import Foundation

enum IndexStateStore {
    static let singletonID = "global_index_state"

    static func fetchOrCreate(in context: ModelContext) throws -> IndexState {
        let descriptor = FetchDescriptor<IndexState>(
            predicate: #Predicate<IndexState> { $0.id == singletonID }
        )

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let state = IndexState(id: singletonID)
        context.insert(state)
        try context.save()
        return state
    }

    static func fetch(in context: ModelContext) throws -> IndexState? {
        let descriptor = FetchDescriptor<IndexState>(
            predicate: #Predicate<IndexState> { $0.id == singletonID }
        )
        return try context.fetch(descriptor).first
    }

    static func save(_ context: ModelContext) throws {
        try context.save()
    }
}
