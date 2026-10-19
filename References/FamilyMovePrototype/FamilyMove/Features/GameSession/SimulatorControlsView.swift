import SwiftUI

struct SimulatorControlsView: View {
    let game: GameType
    let isPlaying: Bool
    let busyPlayers: Set<Int>
    let onMovement: (Int, MovementKind) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if game == .whackAMole {
                Label("Simulator · Click or tap the moles to hit them", systemImage: "cursorarrow.click")
                    .font(.headline)
                    Text("Cyan targets: Player 1 · Pink targets: Player 2").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Simulator · Bird = Duck · Alligator = Jump").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 24) {
                    ForEach(1...2, id: \.self) { id in
                        HStack(spacing: 12) {
                            Text("Player \(id)").font(.subheadline.bold()).foregroundStyle(PlayerStyle.color(for: id))
                            movementButton(.squat, title: "Duck", symbol: "arrow.down", id: id)
                            movementButton(.jump, title: "Jump", symbol: "arrow.up", id: id)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 22).frame(maxWidth: .infinity).frame(height: 104)
        .background(AppColors.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private func movementButton(_ kind: MovementKind, title: String, symbol: String, id: Int) -> some View {
        Button { onMovement(id, kind) } label: {
            Label(title, systemImage: symbol).font(.headline).frame(minWidth: 76, minHeight: 24)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).tint(PlayerStyle.color(for: id))
        .disabled(!isPlaying || busyPlayers.contains(id))
        .accessibilityLabel("Player \(id) \(title)")
        .accessibilityIdentifier("sim\(title)-\(id)")
    }
}

struct SimulatorMoleTargets: View {
    let moles: [Mole]
    let onHit: (Mole) -> Void
    var body: some View {
        ZStack {
            ForEach(moles) { mole in
                Button { onHit(mole) } label: {
                    Circle().fill(.white.opacity(0.001))
                        .frame(width: mole.radius * 2, height: mole.radius * 2).contentShape(Circle())
                }
                .buttonStyle(.plain).position(mole.position)
                .accessibilityLabel("Hit Player \(mole.playerID) mole")
                .accessibilityIdentifier("simMole-\(mole.playerID)")
            }
        }
    }
}

struct SimulatorArenaView: View {
    let players: [TrackedPlayer]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                AppColors.player1.opacity(0.05)
                AppColors.player2.opacity(0.05)
            }
            Rectangle().fill(.gray.opacity(0.15)).frame(width: 1)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ForEach(players) { player in
                let offset = (player.hipCenter?.y ?? geometry.size.height * 0.61) - geometry.size.height * 0.61
                Image(systemName: "figure.stand")
                    .resizable().scaledToFit().frame(height: geometry.size.height * 0.37)
                    .foregroundStyle(PlayerStyle.color(for: player.id).opacity(0.23))
                    .position(x: geometry.size.width * (player.id == 1 ? 0.25 : 0.75), y: geometry.size.height * 0.63 + offset)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: offset)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct SimulatorSetupView: View {
    let game: GameType
    let members: [FamilyMember]
    let isPreparing: Bool
    let onStart: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Text(isPreparing ? "Getting ready…" : "Play on Simulator").font(AppTypography.title)
            Text(game == .whackAMole ? "Click or tap each mole before it disappears."
                 : "Duck for birds. Jump for alligators. Use the controls for each player.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 48) {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    VStack(spacing: 8) {
                        MemberAvatar(member: member, player: index + 1)
                        Text(member.name).font(.headline).lineLimit(1)
                    }
                }
            }.padding(.vertical, 8)
            if isPreparing {
                SwiftUI.ProgressView().accessibilityLabel("Preparing the round")
            } else {
                Button("Start Round", action: onStart).buttonStyle(PrimaryButtonStyle())
                    .frame(width: 260).accessibilityIdentifier("simStartRound")
            }
        }
        .padding(30).frame(maxWidth: 640)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 24)).padding(24)
    }
}
