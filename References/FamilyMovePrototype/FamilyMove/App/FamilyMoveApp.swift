import SwiftUI
import SwiftData

@main
struct FamilyMoveApp: App {
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            let schema = Schema([FamilyMember.self, GameSession.self, ParticipantSessionStat.self, AppSettings.self])
            let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let configuration = uiTesting ? ModelConfiguration("UITestFamilyMove", schema: schema, cloudKitDatabase: .none)
                : ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            let store = try ModelContainer(for: schema, configurations: [configuration])
            if uiTesting && ProcessInfo.processInfo.arguments.contains("--reset-test-store") {
                let context = store.mainContext
                // Batch delete bypasses SwiftData's inverse relationship upkeep.
                // Remove participant links first, then reset only the test store.
                for stat in try context.fetch(FetchDescriptor<ParticipantSessionStat>()) { context.delete(stat) }
                try context.save()
                for session in try context.fetch(FetchDescriptor<GameSession>()) { context.delete(session) }
                for member in try context.fetch(FetchDescriptor<FamilyMember>()) { context.delete(member) }
                for settings in try context.fetch(FetchDescriptor<AppSettings>()) { context.delete(settings) }
                try context.save()
            }
            if uiTesting && ProcessInfo.processInfo.arguments.contains("--seed-test-family") {
                let context = store.mainContext
                if try context.fetchCount(FetchDescriptor<FamilyMember>()) == 0 {
                    context.insert(FamilyMember(name: "Parent", bodyWeightKg: 65))
                    context.insert(FamilyMember(name: "Child", bodyWeightKg: 25, avatarStyle: 1))
                    try context.save()
                }
            }
            container = store
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                AppRootView().modelContainer(container).preferredColorScheme(.light)
                    .onAppear {
                        #if targetEnvironment(macCatalyst)
                        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                            scene.sizeRestrictions?.minimumSize = CGSize(width: 1024, height: 720)
                        }
                        #endif
                    }
            } else {
                ContentUnavailableView("Your family data couldn’t open", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError ?? "Please reopen the app."))
            }
        }
    }
}
