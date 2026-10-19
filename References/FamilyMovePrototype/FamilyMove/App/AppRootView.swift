import SwiftUI
import SwiftData

struct AppRootView: View {
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @StateObject private var coordinator = AppCoordinator()
    var body: some View {
        Group {
            switch coordinator.state {
            case .onboarding:
                OnboardingView(members: members) { coordinator.refresh(profileCount: members.count) }
            case .home: HomeView(members: members, onPlay: coordinator.play)
            case .gameSession:
                GameSessionView(game: coordinator.selectedGame, members: coordinator.selectedMembers) {
                    coordinator.state = .home
                }
            }
        }
        .onAppear { coordinator.refresh(profileCount: members.count) }
        .onChange(of: members.count) { _, count in
            if count < 2 { coordinator.refresh(profileCount: count) }
        }
    }
}
