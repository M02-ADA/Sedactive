import SwiftUI

struct GameHUDView: View {
    let remainingTime: TimeInterval
    let score: Int
    let members: [FamilyMember]
    let players: [TrackedPlayer]
    var immersive = false

    private var timeLabel: String {
        let seconds = Int(ceil(remainingTime))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        if immersive { arcadeHUD } else { standardHUD }
    }

    private var arcadeHUD: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SCORE").font(.caption.bold()).tracking(2)
                    Text("\(score)").font(.system(size: 46, weight: .black, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText()).accessibilityIdentifier("liveScore")
                }.accessibilityElement(children: .contain)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("TIME LEFT").font(.caption.bold()).tracking(2)
                    Text(timeLabel).font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
                }.accessibilityElement(children: .combine)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
            }
            Spacer()
            HStack {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    let detected = players.first { $0.id == index + 1 }?.isDetected == true
                    Label(detected ? "\(member.name) · P\(index + 1)" : "\(member.name) · Move back into view",
                          systemImage: detected ? "person.fill.checkmark" : "person.crop.circle.badge.exclamationmark")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(detected ? ArcadeStyle.handColor(index + 1) : .white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.black.opacity(0.75), in: Capsule())
                        .accessibilityIdentifier("playerStatus-\(index + 1)")
                    if index == 0 { Spacer() }
                }
            }
        }.padding(22).foregroundStyle(.white).allowsHitTesting(false)
    }

    private var standardHUD: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("time left").font(.subheadline)
                    Text(timeLabel).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                }.accessibilityElement(children: .combine)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("score").font(.subheadline)
                    Text("\(score)").accessibilityIdentifier("liveScore").font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                }.accessibilityElement(children: .contain)
            }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            Spacer()
            HStack {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    let detected = players.first { $0.id == index + 1 }?.isDetected == true
                    Label(detected ? "\(member.name) · P\(index + 1)" : "\(member.name) · Move back into view",
                          systemImage: detected ? "person.fill.checkmark" : "person.crop.circle.badge.exclamationmark")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(10).frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: Capsule())
                        .foregroundStyle(index == 0 ? AppColors.player1 : AppColors.player2)
                        .accessibilityIdentifier("playerStatus-\(index + 1)")
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 76).padding(.bottom, 16)
        .allowsHitTesting(false)
    }
}
