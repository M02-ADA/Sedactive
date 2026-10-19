import SwiftUI
import SwiftData

@MainActor
enum HomeViewModel {
    static func greeting(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: now) {
        case 5..<12: return "Good morning,"
        case 12..<18: return "Good afternoon,"
        default: return "Good evening,"
        }
    }
    static func weekly(_ sessions: [GameSession], now: Date = Date()) -> [GameSession] {
        let ids = Set(StatisticsService(sessions: sessions.map(\.record), now: now).weeklySessions().map(\.id))
        return sessions.filter { ids.contains($0.id) }
    }
    static func highScore(_ game: GameType, sessions: [GameSession]) -> Int {
        StatisticsService(sessions: sessions.map(\.record)).highScore(game: game)
    }
}

private enum HomeModal: Identifiable {
    case detail(GameType), players(GameType)
    var id: String {
        switch self { case .detail(let game): return "detail-\(game.rawValue)"
        case .players(let game): return "players-\(game.rawValue)" }
    }
}

struct HomeView: View {
    let members: [FamilyMember]
    let onPlay: (GameType, [FamilyMember]) -> Void
    @Query(sort: \GameSession.startedAt, order: .reverse) private var sessions: [GameSession]
    @State private var progressSelected = false
    @State private var modal: HomeModal?
    var body: some View {
        VStack(spacing: 20) {
            Picker("Home tab", selection: $progressSelected) {
                Text("Games").tag(false); Text("Your Progress").tag(true)
            }.pickerStyle(.segmented).frame(width: 340).accessibilityIdentifier("homeTabs")
            if progressSelected {
                FamilyProgressView(members: members, sessions: sessions)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HomeViewModel.greeting()).font(AppTypography.title)
                        Text("What do you want to play today?").foregroundStyle(.secondary)
                    }
                    Spacer()
                    let weekly = HomeViewModel.weekly(sessions)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This Week’s Activity").font(.caption.bold())
                        HStack(spacing: 24) {
                            Label("\(weekly.count) games", systemImage: "gamecontroller.fill")
                                .accessibilityIdentifier("weeklyHouseholdGames")
                            Label("\(Int(weekly.reduce(0) { $0 + $1.durationSeconds } / 60)) mins being active", systemImage: "clock.fill")
                        }.font(.subheadline.bold())
                    }.padding(18).background(AppColors.secondary, in: RoundedRectangle(cornerRadius: 18))
                }
                HStack(spacing: 22) {
                    ForEach(GameType.allCases) { game in
                        Button { modal = .detail(game) } label: {
                            GameCardView(game: game, highScore: HomeViewModel.highScore(game, sessions: sessions))
                        }.buttonStyle(.plain).accessibilityIdentifier("game-\(game.rawValue)")
                    }
                }
            }
        }
        .padding(AppSpacing.page).background(AppColors.surface)
        .sheet(item: $modal) { item in
            switch item {
            case .detail(let game):
                GameDetailView(game: game, highScore: HomeViewModel.highScore(game, sessions: sessions)) {
                    modal = .players(game)
                }
            case .players(let game):
                PlayerSelectionView(members: members) { selected in
                    modal = nil
                    onPlay(game, selected)
                }
            }
        }
    }
}

struct GameArtwork: View {
    let game: GameType
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if game == .birdsAndAlligators {
                    Image("BirdIllustration").resizable().scaledToFit().rotationEffect(.degrees(-8)).offset(y: -12)
                    Image("AlligatorIllustration").resizable().scaledToFit().offset(y: 18)
                } else { Image("MoleIllustration").resizable().scaledToFit().padding(.horizontal, proxy.size.width * 0.14) }
            }
            .padding(.horizontal, 12).padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

struct GameCardView: View {
    let game: GameType
    let highScore: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .trailing, spacing: 1) {
                Text("your high score").font(.caption)
                Text(highScore, format: .number).font(.system(size: 34, weight: .bold, design: .rounded))
            }.frame(maxWidth: .infinity, alignment: .trailing)
            GameArtwork(game: game).frame(maxHeight: .infinity)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.displayName).font(.title2.bold())
                    Text(game.tagline).font(.subheadline)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill").font(.title)
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.game(game), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.black.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}

struct GameDetailView: View {
    let game: GameType
    let highScore: Int
    let onPlay: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            GameArtwork(game: game).frame(height: 210).background(AppColors.game(game))
                .overlay(alignment: .topTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).padding() }
                        .buttonStyle(.plain).accessibilityLabel("Close game detail")
                }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.displayName).font(.title2.bold()); Text(game.tagline)
                    }
                    Spacer()
                    VStack { Text("your high score").font(.caption); Text("\(highScore)").font(.largeTitle.bold()) }
                }
                Text(game.instructions).font(.subheadline).foregroundStyle(.secondary)
                Button("Play", action: onPlay).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("detailPlay")
            }.padding(24)
        }.presentationDetents([.height(450)])
    }
}
