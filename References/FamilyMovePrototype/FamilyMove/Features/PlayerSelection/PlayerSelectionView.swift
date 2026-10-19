import SwiftUI

@MainActor
final class PlayerSelectionViewModel: ObservableObject {
    @Published private(set) var selectedIDs: [UUID] = []
    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.removeAll { $0 == id } }
        else if selectedIDs.count < 2 { selectedIDs.append(id) }
    }
    func playerNumber(_ id: UUID) -> Int? { selectedIDs.firstIndex(of: id).map { $0 + 1 } }
}

struct PlayerSelectionView: View {
    let members: [FamilyMember]
    let onPlay: ([FamilyMember]) -> Void
    @StateObject private var model = PlayerSelectionViewModel()
    @State private var addingMember = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Who’s Playing?").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .accessibilityLabel("Close player selection")
            }
            Text("Choose two. Player 1 stands on the left; Player 2 stands on the right.")
                .font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(members) { member in
                        Button { model.toggle(member.id) } label: {
                            VStack(spacing: 8) {
                                MemberAvatar(member: member, player: model.playerNumber(member.id))
                                Text(member.name).font(.subheadline)
                            }.opacity(model.playerNumber(member.id) == nil ? 0.55 : 1)
                        }.buttonStyle(.plain).accessibilityIdentifier("select-\(member.name)")
                    }
                    if members.count < 8 {
                        Button { addingMember = true } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.circle.dashed").font(.system(size: 65, weight: .light))
                                Text("Add Player").font(.subheadline)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 10)
            }
            Button("Play") {
                let selected = model.selectedIDs.compactMap { id in members.first { $0.id == id } }
                if selected.count == 2 { onPlay(selected) }
            }.buttonStyle(PrimaryButtonStyle()).disabled(model.selectedIDs.count != 2)
                .opacity(model.selectedIDs.count == 2 ? 1 : 0.45).accessibilityIdentifier("startGame")
        }.padding(28).presentationDetents([.height(360)])
            .sheet(isPresented: $addingMember) { AddMemberView() }
    }
}
