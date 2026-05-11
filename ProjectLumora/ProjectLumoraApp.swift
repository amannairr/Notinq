//
//  ProjectLumoraApp.swift
//  ProjectLumora
//
//  Created by Aman Nair on 11/04/26.
//

import SwiftUI
import SwiftData

@main
struct ProjectLumoraApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainContainerView()
                .background(WindowAccessor())
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .modelContainer(sharedModelContainer)
    }
}
