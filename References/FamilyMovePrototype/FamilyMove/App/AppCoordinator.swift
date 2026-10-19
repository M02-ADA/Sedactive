import SwiftUI

enum AppState { case onboarding, home, gameSession }

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var state = AppState.onboarding
    @Published var selectedGame = GameType.whackAMole
    @Published var selectedMembers: [FamilyMember] = []
    func refresh(profileCount: Int) {
        if state != .gameSession { state = profileCount < 2 ? .onboarding : .home }
    }
    func play(_ game: GameType, members: [FamilyMember]) {
        guard members.count == 2, members[0].id != members[1].id else { return }
        selectedGame = game; selectedMembers = members; state = .gameSession
    }
}
