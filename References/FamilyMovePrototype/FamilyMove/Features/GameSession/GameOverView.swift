import SwiftUI

struct GameOverView: View {
    let game: GameType
    let score: Int
    let members: [FamilyMember]
    let stats: [Int: PlayerRoundStats]
    let saveError: String?
    let onRetry: () -> Void
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(game.displayName).font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done", action: onDone).buttonStyle(.bordered).accessibilityIdentifier("resultsDone")
                }
                HStack(spacing: 36) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Great Moves!").font(AppTypography.title)
                        Text("TOGETHER YOU SCORED").font(.caption).tracking(2)
                        Text("\(score)").font(AppTypography.score).accessibilityIdentifier("finalScore")
                        Button("Play Again", action: onPlayAgain).buttonStyle(PrimaryButtonStyle())
                            .frame(width: 210).accessibilityIdentifier("playAgain")
                    }
                    VStack(spacing: 8) {
                        GameArtwork(game: game).frame(height: 180)
                        Text("Better together.").font(.title2.bold())
                        Text("A little movement. A lot of family fun.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(22)
                    .background(AppColors.game(game), in: RoundedRectangle(cornerRadius: 22))
                }
                HStack(spacing: 16) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        let round = stats[index + 1, default: PlayerRoundStats()]
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(member.name).font(.headline)
                                Spacer()
                                Text("+\(round.scoreContribution) pts").font(.headline.monospacedDigit())
                            }.foregroundStyle(index == 0 ? AppColors.player1 : AppColors.player2)
                            Text(game == .whackAMole
                                 ? "\(round.sideReachCount) side · \(round.overheadReachCount) up · \(round.lowReachCount) low"
                                 : "\(round.squatCount) ducks · \(round.jumpCount) jumps")
                                .font(.subheadline)
                            Text(round.averageReactionTime.map { String(format: "Average reaction %.2f s", $0) }
                                 ?? "Your next adventure is waiting!").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.secondary, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .combine)
                    }
                }
                if let saveError {
                    HStack {
                        Text("Your result hasn’t saved: \(saveError)").font(.caption).foregroundStyle(.red)
                        Button("Retry Save", action: onRetry)
                    }
                } else {
                    Label("Session saved on this device", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(30)
        }
        .frame(maxWidth: 1000).background(AppColors.surface, in: RoundedRectangle(cornerRadius: 28))
        .padding(28)
    }
}
